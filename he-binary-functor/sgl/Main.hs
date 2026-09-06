module Main where

import SGL

main :: IO ()
main = do
    putStrLn "=== Spherical Geometry Language (SGL) Demo ==="
    putStrLn ""

    let sf  = point2 37.7749 (-122.4194)  -- San Francisco
    let nyc = point2 40.7128 (-74.0060)   -- New York City

    let dist = haversine earth sf nyc
    putStrLn $ "SF → NYC distance: " ++ showHaversine dist

    let brng = bearing sf nyc
    putStrLn $ "SF → NYC bearing:  " ++ showBearing brng

    let mid = midpoint sf nyc
    putStrLn $ "Midpoint:          (" ++ show (p2Lat mid) ++ ", " ++ show (p2Lon mid) ++ ")"

    let dest = destinationPoint sf (deg 45) (km 1000)
    putStrLn $ "1000km @ 45° from SF: (" ++ show (p2Lat dest) ++ ", " ++ show (p2Lon dest) ++ ")"

    let lon1 = point2 0 (-122.4194)
    let lon2 = point2 0 (-74.0060)
    let lat1 = point2 37.7749 0
    let lat2 = point2 40.7128 0
    let gc1 = greatCircle earth (vector3 1 0 0)
    let gc2 = greatCircle earth (vector3 0 1 0)
    case intersectGreatCircles gc1 gc2 of
        Just p  -> putStrLn $ "GC intersection:   " ++ show p
        Nothing -> putStrLn "GC intersection:   parallel (no intersection)"

    putStrLn ""
    putStrLn "=== SGL Module Ready ==="
