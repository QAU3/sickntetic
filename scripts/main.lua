Log.setLevel( "ALL" )
json = require "json"

--#region GUI
local  sendRawData = false

--#endregion GUI

-- Create TCP/IP server instance
Server = TCPIPServer.create()
if not Server then
  print('Could not create TCPIPServer')
end
TCPIPServer.setPort(Server, 1234)
-- TCPIPServer.setFraming(Server, '\02', '\03', '\02', '\03') -- STX/ETX framing for transmit and receive
TCPIPServer.listen(Server)

-- Imaging
--Start of Global Scope---------------------------------------------------------
-- Variables, constants, serves etc. should be declared here.
-- Start ROI and Binning Settings
local binningFactor = 1 -- valid values are 1,2,4
local roiSize = {320, 320} -- width must be divisible by 4 after binning
local roiPos = {100, 100}
-- End ROI and Binning Settings
local v2D = View.create()
--local v3D = View.create("Viewer3D")
local v3DRes = View.create("View3DResult")
local cameraModel = nil
local provider = Image.Provider.Camera.create()
local pointCloudConverter = Image.PointCloudConversion.RadialDistance.create()

-- Decoration for Shape
local shapeDeco = View.ShapeDecoration.create()
shapeDeco:setFillColor(255, 20, 147, 100)
shapeDeco:setLineColor(47, 79, 79)
shapeDeco:setLineWidth(2)

-- 2.) Prepare a bounding box to cut out relevant part of the scene. 
local xTranslation = 0
local yTranslation = 100
local zTranlsation = 1000

local xSize = 500
local ySize = 2000
local zSize = 500

local xRotation = 1.05
local yRotation = 0
local zRotation = 0

local segmentSize = 100 -- in mm
local segmentDeco = View.ShapeDecoration.create()
segmentDeco:setFillColor(20, 255, 147, 100)
segmentDeco:setLineColor(47, 79, 79)
segmentDeco:setLineWidth(2)

--box = box:rotateX(1.05)
--v3DRes:addShape(box, shapeDeco)
--v3DRes:present("ASSURED")

local remoteConn = nil
--End of Global Scope-----------------------------------------------------------


---Function is called when a new connection request is coming in
---@param con TCPIPServer.Connection
local function handleConnectionAccepted(con)
  print('Connection is established with ' .. con)
  remoteConn = con
  TCPIPServer.Connection.transmit(con, "\02pong")
end
TCPIPServer.register(Server, 'OnConnectionAccepted', handleConnectionAccepted) -- fixed: register below the function

---Function is called when a connection is closed
---@param con TCPIPServer.Connection
local function handleConnectionClosed(con)
  print('A connection is closed: ' .. con)
end
TCPIPServer.register(Server, 'OnConnectionClosed', handleConnectionClosed)

---Function is called when data is received
---@param con TCPIPServer.Connection
---@param data binary
local function handleReceive(con, data)
  print('Received ' .. tostring(#data) .. ' bytes on con ' .. con)
end

TCPIPServer.register(Server, 'OnReceive', handleReceive)


---Callback funtion which is called when a new image is available
---@param image Image[] table which contains all received images
local function handleOnNewImage(images)
 --region VISUALIZATION
  v2D:clear()
  -- v2D:addDepthmap(substractedImages, cameraModel, nil, {"Depth", "Intensity"})
  v2D:addDepthmap(images, cameraModel, nil, {"Depth", "Intensity"})
  v2D:present()

  local pointCloud = Image.PointCloudConversion.RadialDistance.toPointCloud(pointCloudConverter, images[1],images[2])
  -- local pointCloud = Image.PointCloudConversion.RadialDistance.toPointCloud(pointCloudConverter, substractedImages[1],substractedImages[2])

  --v3D:clear()
  --v3D:addShape(box, shapeDeco)
  --v3D:addPointCloud(pointCloud)
  --v3D:addShape(box,shapeDeco)
  --v3D:present()
 --endregion VISUALIZATION

  -- region PROCESSING
  -- CROP THE POINT CLOUD
  local transform = Transform.createTranslation3D(xTranslation, yTranslation, zTranlsation)
  local box = Shape3D.createBox(xSize, ySize, zSize, transform)
  box = box:rotateX(xRotation):rotateY(yRotation):rotateZ(zRotation)

  --local transformeBox = box:rotateX(xRotation)
  --transformeBox = transformeBox:translate(xTranslation, yTranslation, zTranlsation)

  local inlieres = pointCloud:cropShape(box)
  local cloudCropped = pointCloud:extractIndices(inlieres)
  
  --local shapeFitter = PointCloud.ShapeFitter.create()
  --shapeFitter:setDistanceThreshold(15)
  --local planePoints, inlierIndices = shapeFitter:fitPlane(cloudCropped)
  -- mark all points in the plane
  --cloudCropped:setIntensity(inlierIndices, 1)
  --local cloudFiltered = cloudCropped:extractIndices(inlierIndices, true)
  -- VISUALIZATION of proccesed cloud if available, it NEEDS to uncomment the html code in main.html
  --v3DRes:addPointCloud(cloudFiltered)
  
  v3DRes:clear()
  --v3DRes:addPointCloud(cloudCropped)
  -- Just to visualize the shape mask

  -- TODO: add trnasformation matrix
  local segmentAccumulator = 0
  local offset = -zSize
  while(ySize > segmentAccumulator) do
    local segmentsTransform = Transform.createTranslation3D(xTranslation, offset , segmentAccumulator)
    local segment = Shape3D.createBox(xSize, segmentSize, zSize, segmentsTransform)
    segment = segment:rotateX(xRotation):rotateY(yRotation):rotateZ(zRotation)
    v3DRes:addShape(segment, segmentDeco)
    segmentAccumulator = segmentAccumulator + segmentSize
    offset = offset + 58
  end

  v3DRes:addShape(box, shapeDeco)
  v3DRes:addPointCloud(pointCloud)
  v3DRes:present()
  -- endregion PROCESSING

  --#region TCP
  if remoteConn then 
    -- if sendRawData == true send all data, otherwise the cropped.
    local X, Y, Z, I = (sendRawData and pointCloud or cloudCropped):toVector()
    -- Send the table using start characted \02 to signal begining of new string
    TCPIPServer.Connection.transmit(remoteConn, '\02'..json.encode({X,Y,Z,I}))
  end  
--#endregion TCP
  
  -- local succes = PointCloud.save(cloudCropped, "public/pointCloudTest.ply")
  --if succes then 
  --   print("saved")
  --end
end

local function main()
  Log.info("MAIN CALLED")
   -- Configure frontend
  provider:stop()
  local captureConfig = provider:getConfig()
  captureConfig:setFramePeriod(33333)
  -- Set ROI
  captureConfig:setViewPos(false, roiPos[1], roiPos[2])
  captureConfig:setViewSize(false, roiSize[1], roiSize[2])
  -- Set Binning
  captureConfig:setBinning(binningFactor, binningFactor)

  if provider:setConfig(captureConfig) == false then
    Log.severe("failed to configure capture device")
  end
  -- get camera model (must be updated everytime Roi/Binning is changed)
  cameraModel = Image.Provider.Camera.getInitialCameraModel(provider)
  pointCloudConverter:setCameraModel(cameraModel)
  provider:start()

  -- setup image call back
  provider:register("OnNewImage", handleOnNewImage)
end
--The following registration is part of the global scope which runs once after startup
--Registration of the 'main' function to the 'Engine.OnStarted' event
Script.register("Engine.OnStarted", main)

-- Set queue size to avoid overloading the system
local eventQueueHandle = Script.Queue.create()
eventQueueHandle:setMaxQueueSize(1)
eventQueueHandle:setPriority("HIGH")
eventQueueHandle:setFunction(handleOnNewImage)

--#region GUI BINDINGS
---Sets the current frameperiod in ms
---@param change float frameperiod in ms
local function setFramePeriod(change)
  local currentConfig = provider:getConfig()
  local framePeriodUs = change * 1000
  currentConfig:setFramePeriod(framePeriodUs)
  provider:setConfig(currentConfig)
end

Script.serveFunction("Visionary_T_Mini_AP_SplitViewer.setFramePeriod", setFramePeriod)

---Gets the current frameperiod in ms
---@return float frameperiod in ms
local function getFramePeriod()
  local currentConfig = provider:getConfig()
  local framePeriodUs = currentConfig:getFramePeriod() / 1000
  return framePeriodUs
end
Script.serveFunction("Visionary_T_Mini_AP_SplitViewer.getFramePeriod", getFramePeriod)

---Gets current state of distance filter
---@return bool true if distance filter is enabled
local function getDistanceFilterEnabled()
  local currentConfig = provider:getConfig()
  local enabled = currentConfig:getDistanceFilter()
  return enabled
end
Script.serveFunction("Visionary_T_Mini_AP_SplitViewer.getDistanceFilterEnabled", getDistanceFilterEnabled)

---sets current state of distance filter
---@param change bool true to enable distance filter
local function setDistanceFilterEnabled(change)
  local currentConfig = provider:getConfig()
  currentConfig:setDistanceFilter(change)
  provider:setConfig(currentConfig)
end
Script.serveFunction("Visionary_T_Mini_AP_SplitViewer.setDistanceFilterEnabled", setDistanceFilterEnabled)

---sets current range of distance filter
---@param range float range of distance filter
local function setDistanceFilterRange(range)
  local currentConfig = provider:getConfig()
  -- Assume the filter is enabled if range is changed
  currentConfig:setDistanceFilter(true, range[1], range[2])
  provider:setConfig(currentConfig)
end
Script.serveFunction("Visionary_T_Mini_AP_SplitViewer.setDistanceFilterRange", setDistanceFilterRange)

---gets current range of distance filter
---@return range float range of distance filter
local function getDistanceFilterRange()
  local currentConfig = provider:getConfig()
  local _, min, max = currentConfig:getDistanceFilter()
  return {min, max}
end
Script.serveFunction("Visionary_T_Mini_AP_SplitViewer.getDistanceFilterRange", getDistanceFilterRange)

---Gets current state of intensity filter
---@return bool true if intensity filter is enabled
local function getIntensityFilterEnabled()
  local currentConfig = provider:getConfig()
  local enabled = currentConfig:getIntensityFilter()
  return enabled
end
Script.serveFunction("Visionary_T_Mini_AP_SplitViewer.getIntensityFilterEnabled", getIntensityFilterEnabled)

---gets current range of intensity filter
---@return range float range of intensity filter
local function getIntensityFilterRange()
  local currentConfig = provider:getConfig()
  local _, min, max = currentConfig:getIntensityFilter()
  -- convert from linear to db
  if min > 0 then
    min = 20.0 * math.log(min, 10)
  end
  if max > 0 then
    max = 20.0 * math.log(max, 10)
  end
  return {min, max}
end
Script.serveFunction("Visionary_T_Mini_AP_SplitViewer.getIntensityFilterRange", getIntensityFilterRange)

---Sets current state of intensity filter
---@param change bool true to enable intensity filter
local function setIntensityFilterEnabled(change)
  local currentConfig = provider:getConfig()
  currentConfig:setIntensityFilter(change)
  provider:setConfig(currentConfig)
end
Script.serveFunction("Visionary_T_Mini_AP_SplitViewer.setIntensityFilterEnabled", setIntensityFilterEnabled)


---sets current range of intensity filter
---@param range float range of intensity filter
local function setIntensityFilterRange(range)
  local currentConfig = provider:getConfig()
  -- convert from db to linear
  local minValue = 10 ^ (range[1] / 20)
  local maxValue = 10 ^ (range[2] / 20)
  -- Assume the filter is enabled if range is changed
  currentConfig:setIntensityFilter(true, minValue, maxValue)
  provider:setConfig(currentConfig)
end
Script.serveFunction("Visionary_T_Mini_AP_SplitViewer.setIntensityFilterRange", setIntensityFilterRange)

---Gets current state of isolated pixel filter
---@return bool true if isolated pixel filter is enabled
local function getIsoPixFilter()
  local currentConfig = provider:getConfig()
  local enabled = currentConfig:getFlyingClusterFilter()
  return enabled
end
Script.serveFunction("Visionary_T_Mini_AP_SplitViewer.getIsoPixFilter", getIsoPixFilter)

---Gets current value of isolated pixel filter
---@return float current value of filter
local function getIsoPixValue()
  local currentConfig = provider:getConfig()
  local _, value = currentConfig:getFlyingClusterFilter()
  return value
end
Script.serveFunction("Visionary_T_Mini_AP_SplitViewer.getIsoPixValue", getIsoPixValue)

---Sets current state of isolated pixel filter
---@param change bool true to enable isolated pixel filter
local function setIsoPixFilterEnabled(change)
  local currentConfig = provider:getConfig()
  currentConfig:setFlyingClusterFilter(change)
  provider:setConfig(currentConfig)
end
Script.serveFunction("Visionary_T_Mini_AP_SplitViewer.setIsoPixFilterEnabled", setIsoPixFilterEnabled)

---Sets current value of isolated pixel filter
---@param value float value of filter
local function setIsoPixFilterValue(value)
  local currentConfig = provider:getConfig()
  -- Assume the filter is enabled if value is changed
  currentConfig:setIntensityFilter(true, value)
  provider:setConfig(currentConfig)
end
Script.serveFunction("Visionary_T_Mini_AP_SplitViewer.setIsoPixFilterValue", setIsoPixFilterValue)

---Gets current state of ambiguity filter
---@return bool true if ambiguity filter is enabled
local function getAmbiguityFilterEnabled()
  local currentConfig = provider:getConfig()
  local enabled = currentConfig:getAmbiguityFilter()
  return enabled
end
Script.serveFunction("Visionary_T_Mini_AP_SplitViewer.getAmbiguityFilterEnabled", getAmbiguityFilterEnabled)

---Gets current value of ambiguity filter
---@return float current value of filter
local function getAmbiguityFilterValue()
  local currentConfig = provider:getConfig()
  local _, value = currentConfig:getAmbiguityFilter()
  return value
end
Script.serveFunction("Visionary_T_Mini_AP_SplitViewer.getAmbiguityFilterValue", getAmbiguityFilterValue)

---Sets current state of ambiguity filter
---@param change bool true to enable ambiguity filter
local function setAmbiguityFilterEnabled(change)
  local currentConfig = provider:getConfig()
  currentConfig:setAmbiguityFilter(change)
  provider:setConfig(currentConfig)
end
Script.serveFunction("Visionary_T_Mini_AP_SplitViewer.setAmbiguityFilterEnabled", setAmbiguityFilterEnabled)

---Sets current value of ambiguity filter
---@param value float value of filter
local function setAmbiguityFilter(value)
  local currentConfig = provider:getConfig()
  -- Assume the filter is enabled if value is changed
  currentConfig:setAmbiguityFilter(true, value)
  provider:setConfig(currentConfig)
end
Script.serveFunction("Visionary_T_Mini_AP_SplitViewer.setAmbiguityFilter", setAmbiguityFilter)

---Gets current state of remission filter
---@return bool true if remission filter is enabled
local function getRemisssionFilterEnabled()
  local currentConfig = provider:getConfig()
  local enabled = currentConfig:getRemissionFilter()
  return enabled
end
Script.serveFunction("Visionary_T_Mini_AP_SplitViewer.getRemisssionFilterEnabled", getRemisssionFilterEnabled)

---gets current range of remission filter
---@return range float range of remission filter
local function getRemissionFilterRange()
  local currentConfig = provider:getConfig()
  local _, min, max = currentConfig:getRemissionFilter()
  return {min, max}
end
Script.serveFunction("Visionary_T_Mini_AP_SplitViewer.getRemissionFilterRange", getRemissionFilterRange)

---Sets current state of remission filter
---@param change bool true to enable remission filter
local function setRemissionFilterEnabled(change)
  local currentConfig = provider:getConfig()
  currentConfig:setRemissionFilter(change)
  provider:setConfig(currentConfig)
end
Script.serveFunction("Visionary_T_Mini_AP_SplitViewer.setRemissionFilterEnabled", setRemissionFilterEnabled)

---sets current range of remission filter
---@param range float range of remission filter
local function setRemissionFilterRange(range)
  local currentConfig = provider:getConfig()
  -- Assume the filter is enabled if range is changed
  currentConfig:setRemissionFilter(true, range[1], range[2])
  provider:setConfig(currentConfig)
end
Script.serveFunction("Visionary_T_Mini_AP_SplitViewer.setRemissionFilterRange", setRemissionFilterRange)

---Gets current state of edge correction
---@return bool true if edge correction is enabled
local function getEdgeCorrectionEnabled()
  local currentConfig = provider:getConfig()
  local enabled, _, _ = currentConfig:getEdgeCorrection()
  return enabled
end
Script.serveFunction("Visionary_T_Mini_AP_SplitViewer.getEdgeCorrectionEnabled", getEdgeCorrectionEnabled)

---Sets state of edge correction
---@return bool true to enable edge correction
local function setEdgeCorrectionEnabled(enabled)
  local currentConfig = provider:getConfig()
  -- Assume the filter is enabled if range is changed
  currentConfig:setEdgeCorrection(enabled)
  provider:setConfig(currentConfig)
end

Script.serveFunction("Visionary_T_Mini_AP_SplitViewer.setEdgeCorrectionEnabled", setEdgeCorrectionEnabled)

--@onSendRawChanged(change:bool):
local function onSendRawChanged(change)
  sendRawData= change=="true" and true or false

end
Script.serveFunction("Visionary_T_Mini_AP_SplitViewer.onSendRawChanged", onSendRawChanged)

--#endregion GUI BINDINGS

--End of Function and Event Scope-----------------------------------------------

--@onYTranslateChanged(change:string):
local function onYTranslateChanged(change)
  yTranslation = tonumber(change)
end
Script.serveFunction("Visionary_T_Mini_AP_SplitViewer.onYTranslateChanged", onYTranslateChanged)

--@onZTranslateChanged(change:string):
local function onZTranslateChanged(change)
  zTranlsation = tonumber(change)
end
Script.serveFunction("Visionary_T_Mini_AP_SplitViewer.onZTranslateChanged", onZTranslateChanged)

--@onXTranslateChanged(change:string):
local function onXTranslateChanged(change)
  xTranslation = tonumber(change)
end
Script.serveFunction("Visionary_T_Mini_AP_SplitViewer.onXTranslateChanged", onXTranslateChanged)

--@onXSizeChanged(change:string):
local function onXSizeChanged(change)
  xSize = tonumber(change)
end
Script.serveFunction("Visionary_T_Mini_AP_SplitViewer.onXSizeChanged", onXSizeChanged)

--@onYSizeChanged(change:string):
local function onYSizeChanged(change)
  ySize = tonumber(change)
end
Script.serveFunction("Visionary_T_Mini_AP_SplitViewer.onYSizeChanged", onYSizeChanged)

--@onZSizeChanged(change:string):
local function onZSizeChanged(change)
  zSize = tonumber(change)
end
Script.serveFunction("Visionary_T_Mini_AP_SplitViewer.onZSizeChanged", onZSizeChanged)

--@onXRotationChanged(change:string):
local function onXRotationChanged(change)
  xRotation = tonumber(change)
end
Script.serveFunction("Visionary_T_Mini_AP_SplitViewer.onXRotationChanged", onXRotationChanged)

--@onYRotationChanged(change:string):
local function onYRotationChanged(change)
  yRotation = tonumber(change)
end
Script.serveFunction("Visionary_T_Mini_AP_SplitViewer.onYRotationChanged", onYRotationChanged)

--@onZRotationChanged(change:string):
local function onZRotationChanged(change)
  zRotation = tonumber(change)
end
Script.serveFunction("Visionary_T_Mini_AP_SplitViewer.onZRotationChanged", onZRotationChanged)