
-- GTAS_RouteConnections - Part of Really Advanced Setup Mod

-- A big thank you to whoward69 for writing this code.
--
--
-- RouteConnections.lua
--
-- Copyright 2011  (c)  William Howard
--
-- Determines if a route exists between two plots/cities
--
-- Permission granted to re-distribute this file as part of a mod
-- on the condition that this comment block is preserved in its entirity
--

include("FLuaVector")

----- PUBLIC METHODS -----

-- Array of route types - you can change the text, but NOT the order
routes = {"Land", "Road", "Railroad", "Coastal", "Ocean", "Submarine"}

-- Array of highlight colours
highlights = { Red     = Vector4(1.0, 0.0, 0.0, 1.0), 
               Green   = Vector4(0.0, 1.0, 0.0, 1.0), 
               Blue    = Vector4(0.0, 0.0, 1.0, 1.0),
               Cyan    = Vector4(0.0, 1.0, 1.0, 1.0),
               Yellow  = Vector4(1.0, 1.0, 0.0 ,1.0),
               Magenta = Vector4(1.0, 0.0, 1.0, 1.0),
               Black   = Vector4(0.5, 0.5, 0.5, 1.0)}             

--
-- pPlayer                 - player object (not ID) or nil
-- pStartCity, pTargetCity - city objects (not IDs)
-- pStartPlot, pTargetPlot - plot objects (not IDs)
-- sRoute                  - one of routes (see above)
-- bShortestRoute          - true to find the shortest route
-- sHighlight              - one of the highlight keys (see above)
-- fBlockaded              - call-back function of the form f(pPlot, pPlayer) to determine if a plot is blocked for this player (return true if blocked)
--

function isCityConnected(pPlayer, pStartCity, pTargetCity, sRoute, bShortestRoute, sHighlight, fBlockaded)
  return isPlotConnected(pPlayer, pStartCity:Plot(), pTargetCity:Plot(), sRoute, bShortestRoute, sHighlight, fBlockaded)
end

function isPlotConnected(pPlayer, pStartPlot, pTargetPlot, sRoute, bShortestRoute, sHighlight, fBlockaded)
  if (bShortestRoute) then
    lastRouteLength = plotToPlotShortestRoute(pPlayer, pStartPlot, pTargetPlot, sRoute, highlights[sHighlight], fBlockaded)
  else
    lastRouteLength = plotToPlotConnection(pPlayer, pStartPlot, pTargetPlot, sRoute, 1, highlights[sHighlight], listAddPlot(pStartPlot, {}), fBlockaded)
  end

  return (lastRouteLength ~= 0)
end

function getRouteLength()
  return lastRouteLength
end

function getDistance(pPlot1, pPlot2)
  return distanceBetween(pPlot1, pPlot2)
end


-- function playerCapitalToMinorCivShortestRoute(pPlayer, sRoute, highlight, fBlockaded)
  -- local pStartPlot = nil;
  -- local pTargetPlot = pPlayer:GetCapitalCity():Plot(); -- Just don't ask why I wrote this code backwards!!!
  -- local rings = {};
  -- local iRing = 1;
  -- rings[iRing] = listAddPlot(pTargetPlot, {});

  -- repeat
    -- iRing = generateNextRing(pPlayer, sRoute, rings, iRing, fBlockaded);
    -- pStartPlot = listContainsAnyMinorCapital(rings[iRing]);
    -- bFound = (pStartPlot ~= nil);
    -- bNoRoute = (rings[iRing] == nil);
  -- until (bFound or bNoRoute);

  -- return (bFound) and iRing or 0;
-- end

-- -- Return the first plot in the list which is a minor civ capital
-- function listContainsAnyMinorCapital(list)
  -- for _, pPlot in pairs(list) do
    -- local pCity = pPlot:GetPlotCity()
	
	-- if (pCity ~= nil and pCity:IsCapital()) then
	  -- if (Players[pCity:GetOwner()]:IsMinorCiv()) then
	    -- return pPlot
	  -- end
	-- end
	
  -- end
  
  -- return nil
-- end


----- PRIVATE DATA AND METHODS -----

lastRouteLength = 0

--
-- Check if pStartPlot is connected to pTargetPlot
--
-- NOTE: This is a recursive method
--
-- Returns the length of the route between the start and target plots (inclusive) - so 0 if no route
--

function plotToPlotConnection(pPlayer, pStartPlot, pTargetPlot, sRoute, iLength, highlight, listVisitedPlots, fBlockaded)
  if (highlight ~= nil) then
    Events.SerialEventHexHighlight(PlotToHex(pStartPlot), true, highlight)
  end

  -- Have we got there yet?
  if (isSamePlot(pStartPlot, pTargetPlot)) then
    return iLength
  end

  -- Find any new plots we can visit from here
  local listRoutes = listFilter(reachablePlots(pPlayer, pStartPlot, sRoute, fBlockaded), listVisitedPlots)

  -- New routes to check, so there is an onward path
  if (listRoutes ~= nil) then
    -- Covert the associative array into a linear array so it can be sorted
    local array = {}
    for sId, pPlot in pairs(listRoutes) do
      table.insert(array, pPlot)
    end

    -- Now sort the linear array by distance from the target plot
    table.sort(array, function(x, y) return (distanceBetween(x, pTargetPlot) < distanceBetween(y, pTargetPlot)) end)

    -- Now check each onward plot in turn to see if that is connected
    for i, pPlot in ipairs(array) do
      -- Check that a prior route didn't visit this plot
      if (not listContainsPlot(pPlot, listVisitedPlots)) then
        -- Add this plot to the list of visited plots
        listAddPlot(pPlot, listVisitedPlots)

        -- If there's a route, we're done
        local iLen = plotToPlotConnection(pPlayer, pPlot, pTargetPlot, sRoute, iLength+1, highlight, listVisitedPlots, fBlockaded)
        if (iLen > 0) then
          return iLen
        end
      end
    end
  end

  if (highlight ~= nil) then
    Events.SerialEventHexHighlight(PlotToHex(pStartPlot), false)
  end

  -- No connection found
  return 0
end


--
-- Find the shortest route between two plots
--
-- We start at the TARGET plot - as the path length from here to the target plot is 1,
-- we will call this "ring 1".  We then find all reachable adjacent plots and place them in "ring 2".
-- If the START plot is in "ring 2", we have a route, if "ring 2" is empty, there is no route,
-- otherwise find all reachable adjacent plots that have not already been seen and place those in "ring 3"
-- We then loop, checking "ring N" otherwise generating "ring N+1"
--
-- Once we have found a route, the path length will be of length N and we know that there must be at 
-- least one route by picking a plot from each ring.  The plot needed from "ring N" is the START plot,
-- we then need ANY plot from "ring N-1" that is adjacent to the start plot. And in general we need 
-- any plot from "ring M-1" that is adjacent to the plot choosen from "ring M".  The final plot in 
-- the path will always be the target plot as that is the only plot in "ring 1"
--
-- Returns the length of the route between the start and target plots (inclusive) - so 0 if no route
--

function plotToPlotShortestRoute(pPlayer, pStartPlot, pTargetPlot, sRoute, highlight, fBlockaded)
  local rings = {}

  local iRing = 1
  rings[iRing] = listAddPlot(pTargetPlot, {})

  repeat
    iRing = generateNextRing(pPlayer, sRoute, rings, iRing, fBlockaded)

    bFound = listContainsPlot(pStartPlot, rings[iRing])
    bNoRoute = (rings[iRing] == nil)
  until (bFound or bNoRoute)

  if (bFound and highlight ~= nil) then
    Events.SerialEventHexHighlight(PlotToHex(pStartPlot), true, highlight)

    local pLastPlot = pStartPlot

    for i = iRing - 1, 1, -1 do
      pNextPlot = listFirstAdjacentPlot(pLastPlot, rings[i])
      
      -- Check should be completely unnecessary
      if (pNextPlot == nil) then
        return 0
      end

      Events.SerialEventHexHighlight(PlotToHex(pNextPlot), true, highlight)

      pLastPlot = pNextPlot
    end
  end  
  
  return (bFound) and iRing or 0
end

-- Helper method to find all plots adjacent to the plots in the specified ring
function generateNextRing(pPlayer, sRoute, rings, iRing, fBlockaded)
  local nextRing = nil

  for k, pPlot in pairs(rings[iRing]) do
    -- Consider two adjacent tiles A and B,  if A is in ring N, B must either be unvisited or in ring N-1
    -- for if B was in ring N-2, A would have to be in ring N-1 - which it is not
    local listRoutes = listFilter(reachablePlots(pPlayer, pPlot, sRoute, fBlockaded), ((iRing > 1) and rings[iRing-1] or {}))

    if (listRoutes ~= nil) then
      for sId, pPlot in pairs(listRoutes) do
        nextRing = nextRing or {}
        listAddPlot(pPlot, nextRing)
      end
    end
  end

  rings[iRing+1] = nextRing

  return iRing+1
end


--
-- Methods dealing with finding all adjacent tiles that can be reached by the specified route type
--

-- Array of directions, since changing to proximity based decision making, the order is not important
directions = {DirectionTypes.DIRECTION_NORTHEAST, DirectionTypes.DIRECTION_EAST, DirectionTypes.DIRECTION_SOUTHEAST,
              DirectionTypes.DIRECTION_SOUTHWEST, DirectionTypes.DIRECTION_WEST, DirectionTypes.DIRECTION_NORTHWEST}

-- Return a list of (up to 6) reachable plots from this one by route type
function reachablePlots(pPlayer, pPlot, sRoute, fBlockaded)
  local list = nil

  for loop, direction in ipairs(directions) do
    local pDestPlot = Map.PlotDirection(pPlot:GetX(), pPlot:GetY(), direction)

    -- Don't let submarines fall over the edge!
    if (pDestPlot ~= nil) then
      if (pPlayer == nil or pDestPlot:IsRevealed(pPlayer:GetTeam())) then
        local bAdd = false

        -- Be careful of order, must check for road before rail, and coastal before ocean
        if (sRoute == routes[1] and (pDestPlot:GetPlotType() == PlotTypes.PLOT_LAND or pDestPlot:GetPlotType() == PlotTypes.PLOT_HILLS)) then
          bAdd = true
        elseif (sRoute == routes[2] and pDestPlot:GetRouteType() >= 0) then
          bAdd = true
        elseif (sRoute == routes[3] and pDestPlot:GetRouteType() >= 1) then
          bAdd = true
        elseif (sRoute == routes[4] and pDestPlot:GetTerrainType() == TerrainTypes.TERRAIN_COAST) then
          bAdd = true
        elseif (sRoute == routes[5] and pDestPlot:IsWater()) then
          bAdd = true
        elseif (sRoute == routes[6] and pDestPlot:IsWater()) then
          bAdd = true
        end

        -- Special case for water, a city on the coast counts as water
        if (not bAdd and (sRoute == routes[4] or sRoute == routes[5] or sRoute == routes[6])) then
          bAdd = pDestPlot:IsCity()
        end

        -- Check for impassable and blockaded tiles
        bAdd = bAdd and isPassable(pDestPlot, sRoute) and not isBlockaded(pDestPlot, pPlayer, fBlockaded)

        if (bAdd) then
          list = list or {}
          listAddPlot(pDestPlot, list)
        end
      end
    end
  end

  return list
end

-- Is the plot passable for this route type ...
function isPassable(pPlot, sRoute)
  bPassable = true

  -- ... due to terrain, eg natural wonders and those covered in ice
  iFeature = pPlot:GetFeatureType()
  if (GameInfo.Features[iFeature] and GameInfo.Features[iFeature].NaturalWonder == true) then
    bPassable = false
  elseif (iFeature == FeatureTypes.FEATURE_ICE and sRoute ~= routes[6]) then
    bPassable = false
  end

  return bPassable
end

-- Is the plot blockaded for this player ...
function isBlockaded(pPlot, pPlayer, fBlockaded)
  bBlockaded = false

  if (fBlockaded ~= nil) then
    bBlockaded = fBlockaded(pPlot, pPlayer)
  end

  return bBlockaded
end



--
-- Calculate the distance between two plots
--
-- See http://www-cs-students.stanford.edu/~amitp/Articles/HexLOS.html
-- Also http://keekerdc.com/2011/03/hexagon-grids-coordinate-systems-and-distance-calculations/
--
function distanceBetween(pPlot1, pPlot2)
  local mapX, mapY = Map.GetGridSize()

  -- Need to work on a hex based grid
  local hex1 = PlotToHex(pPlot1)
  local hex2 = PlotToHex(pPlot2)

  -- Calculate the distance between the x and z co-ordinate pairs
  -- allowing for the East-West wrap, (ie shortest route may be by going backwards!)
  local deltaX = math.min(math.abs(hex2.x - hex1.x), mapX - math.abs(hex2.x - hex1.x))
  local deltaZ = math.min(math.abs(hex2.z - hex1.z), mapX - math.abs(hex2.z - hex1.z))

  -- Calculate the distance between the y co-ordinates
  -- there is no North-South wrap, so this is easy
  local deltaY = math.abs(hex2.y - hex1.y)

  -- Calculate the distance between the plots
  local distance = math.max(deltaX, deltaY, deltaZ)

  -- Allow for both end points in the distance calculation
  return distance + 1
end

-- Get the hex co-ordinates of a plot
function PlotToHex(pPlot)
  local hex = ToHexFromGrid(Vector2(pPlot:GetX(), pPlot:GetY()))

  -- X + y + z = 0, hence z = -(x+y)
  hex.z = -(hex.x + hex.y)

  return hex
end


--
-- List (associative arrays) helper methods
--

-- Return a list formed by removing all entries from list1 which are in list2
function listFilter(list1, list2)
  local list = nil

  if (list1 ~= nil) then
    for sKey, pPlot in pairs(list1) do
      if (list2 == nil or list2[sKey] == nil) then
        list = list or {}
        list[sKey] = pPlot
      end
    end
  end

  return list
end

-- Return true if pPlot is in list
function listContainsPlot(pPlot, list)
  return (list ~= nil and list[getPlotKey(pPlot)] ~= nil)
end

-- Add the plot to the list
function listAddPlot(pPlot, list)
  if (list ~= nil) then
    list[getPlotKey(pPlot)] = pPlot
  end

  return list
end

function listFirstAdjacentPlot(pPlot, list)
  for key, plot in pairs(list) do
    if (distanceBetween(pPlot, plot) == 2) then
      return plot
    end
  end

  -- We should NEVER reach here
  return nil
end


--
-- Plot helper methods
--

-- Are the plots one and the same?
function isSamePlot(pPlot1, pPlot2)
  return (pPlot1:GetX() == pPlot2:GetX() and pPlot1:GetY() == pPlot2:GetY())
end

-- Get a unique key for the plot
function getPlotKey(pPlot)
  return string.format("%d:%d", pPlot:GetX(), pPlot:GetY())
end

-- Get the grid-based (x, y) co-ordinates of the plot as a string
function plotToGridStr(pPlot)
  if (pPlot == nil) then return "" end

  return string.format("(%d, %d)", pPlot:GetX(), pPlot:GetY())
end

-- Get the hex-based (x, y, z) co-ordinates of the plot as a string
function plotToHexStr(pPlot)
  if (pPlot == nil) then return "" end

  local hex = PlotToHex(pPlot)

  return string.format("(%d, %d, %d)", hex.x, hex.y, hex.z)
end
