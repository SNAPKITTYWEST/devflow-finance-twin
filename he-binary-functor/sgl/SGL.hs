module SGL (
    -- * Types
    Angle(..), Length(..), Radius(..),
    Point2(..), Point3(..), Vector3(..),
    Sphere(..), PointOn(..), GreatCircle(..), Arc(..),
    -- * Constructors
    km, nm, deg, rad, earth,
    point2, point3, vector3,
    pointOnSphere, greatCircle, arc,
    -- * Operations
    haversine, bearing, midpoint,
    destinationPoint, intersectGreatCircles,
    areaOfSphericalTriangle,
    normalizeAngle, toDegrees, toRadians,
    -- * Rendering
    showHaversine, showBearing, showArea
) where

import Data.Fixed (mod')

-- | Angular measurement
newtype Angle = Angle Double deriving (Eq, Ord)

-- | Linear distance
newtype Length = Length Double deriving (Eq, Ord)

-- | Spherical radius
newtype Radius = Radius Double deriving (Eq, Ord)

-- | 2D point (latitude, longitude in degrees)
data Point2 = Point2
    { p2Lat :: !Double
    , p2Lon :: !Double
    } deriving (Eq, Show)

-- | 3D point on unit sphere
data Point3 = Point3
    { p3X :: !Double
    , p3Y :: !Double
    , p3Z :: !Double
    } deriving (Eq, Show)

-- | 3D vector
data Vector3 = Vector3
    { v3X :: !Double
    , v3Y :: !Double
    , v3Z :: !Double
    } deriving (Eq, Show)

-- | Sphere with radius
data Sphere = Sphere
    { sRadius :: !Radius
    , sCenter :: !Point3
    } deriving (Eq, Show)

-- | Point constrained to a sphere
data PointOn = PointOn
    { poSphere :: !Sphere
    , poPoint  :: !Point3
    } deriving (Eq, Show)

-- | Great circle on a sphere
data GreatCircle = GreatCircle
    { gcSphere  :: !Sphere
    , gcNormal  :: !Vector3
    } deriving (Eq, Show)

-- | Arc between two points on a great circle
data Arc = Arc
    { arcStart :: !PointOn
    , arcEnd   :: !PointOn
    , arcAngle :: !Angle
    } deriving (Eq, Show)

-- Constructors
km :: Double -> Length
km = Length

nm :: Double -> Length
nm = Length

deg :: Double -> Angle
deg = Angle

rad :: Double -> Angle
rad = Angle

earth :: Sphere
earth = Sphere
    { sRadius = Radius 6371.0
    , sCenter = Point3 0 0 0
    }

point2 :: Double -> Double -> Point2
point2 = Point2

point3 :: Double -> Double -> Double -> Point3
point3 = Point3

vector3 :: Double -> Double -> Double -> Vector3
vector3 = Vector3

pointOnSphere :: Sphere -> Point3 -> PointOn
pointOnSphere = PointOn

greatCircle :: Sphere -> Vector3 -> GreatCircle
greatCircle = GreatCircle

arc :: PointOn -> PointOn -> Arc
arc s e = Arc s e (Angle 0)  -- angle computed from haversine

-- | Convert degrees to radians
toRadians :: Angle -> Double
toRadians (Angle d) = d * pi / 180.0

-- | Convert radians to degrees
toDegrees :: Angle -> Angle
toDegrees (Angle r) = Angle (r * 180.0 / pi)

-- | Normalize angle to [0, 360)
normalizeAngle :: Angle -> Angle
normalizeAngle (Angle a) = Angle (mod' a 360.0)

-- | Haversine distance between two points
haversine :: Sphere -> Point2 -> Point2 -> Length
haversine (Sphere (Radius r) _) (Point2 lat1 lon1) (Point2 lat2 lon2) =
    let dLat = toRadians (Angle (lat2 - lat1))
        dLon = toRadians (Angle (lon2 - lon1))
        a = sin (toRadians dLat / 2) ** 2
            + cos (toRadians (Angle lat1))
            * cos (toRadians (Angle lat2))
            * sin (toRadians dLon / 2) ** 2
        c = 2 * atan2 (sqrt a) (sqrt (1 - a))
    in Length (r * c)

-- | Initial bearing from point 1 to point 2
bearing :: Point2 -> Point2 -> Angle
bearing (Point2 lat1 lon1) (Point2 lat2 lon2) =
    let dLon = toRadians (Angle (lon2 - lon1))
        y = sin (toRadians dLon) * cos (toRadians (Angle lat2))
        x = cos (toRadians (Angle lat1)) * sin (toRadians (Angle lat2))
            - sin (toRadians (Angle lat1)) * cos (toRadians (Angle lat2))
            * cos (toRadians dLon)
        brng = atan2 y x
    in normalizeAngle (Angle (brng * 180.0 / pi))

-- | Midpoint between two points
midpoint :: Point2 -> Point2 -> Point2
midpoint (Point2 lat1 lon1) (Point2 lat2 lon2) =
    let dLon = toRadians (Angle (lon2 - lon1))
        bx = cos (toRadians (Angle lat2)) * cos (toRadians dLon)
        by = cos (toRadians (Angle lat2)) * sin (toRadians dLon)
        lat = atan2 (sin (toRadians (Angle lat1)) + sin (toRadians (Angle lat2)))
                     (sqrt ((cos (toRadians (Angle lat1)) + bx) ** 2 + by ** 2))
        lon = toRadians (Angle lon1) + atan2 by (cos (toRadians (Angle lat1)) + bx)
    in Point2 (lat * 180.0 / pi) (lon * 180.0 / pi)

-- | Destination point given start, bearing, and distance
destinationPoint :: Point2 -> Angle -> Length -> Point2
destinationPoint (Point2 lat1 lon1) brng (Length d) =
    let r = 6371.0  -- Earth radius in km
        angDist = d / r
        lat1r = toRadians (Angle lat1)
        lon1r = toRadians (Angle lon1)
        brngr = toRadians brng
        lat2 = asin (sin lat1r * cos angDist
                   + cos lat1r * sin angDist * cos brngr)
        lon2 = lon1r + atan2 (sin brngr * sin angDist * cos lat1r)
                             (cos angDist - sin lat1r * sin lat2)
    in Point2 (lat2 * 180.0 / pi) (lon2 * 180.0 / pi)

-- | Intersection of two great circles (simplified)
intersectGreatCircles :: GreatCircle -> GreatCircle -> Maybe Point3
intersectGreatCircles (GreatCircle _ n1) (GreatCircle _ n2) =
    let Vector3 x1 y1 z1 = n1
        Vector3 x2 y2 z2 = n2
        ix = y1 * z2 - z1 * y2
        iy = z1 * x2 - x1 * z2
        iz = x1 * y2 - y1 * x2
        mag = sqrt (ix*ix + iy*iy + iz*iz)
    in if mag < 1e-10
       then Nothing
       else Just (Point3 (ix/mag) (iy/mag) (iz/mag))

-- | Area of spherical triangle (spherical excess)
areaOfSphericalTriangle :: Sphere -> Point2 -> Point2 -> Point2 -> Double
areaOfSphericalTriangle (Sphere (Radius r) _) a b c =
    let a' = toRadians (Angle (p2Lat a))
        b' = toRadians (Angle (p2Lat b))
        c' = toRadians (Angle (p2Lat c))
        dAB = toRadians (Angle (p2Lon b - p2Lon a))
        dBC = toRadians (Angle (p2Lon c - p2Lon b))
        dCA = toRadians (Angle (p2Lon a - p2Lon c))
        ex = atan (tan (a'/2) * tan (dAB/2) / tan (b'/2))
           + atan (tan (b'/2) * tan (dBC/2) / tan (c'/2))
           + atan (tan (c'/2) * tan (dCA/2) / tan (a'/2))
    in abs ex * r * r

-- | Show haversine result
showHaversine :: Length -> String
showHaversine (Length d) = show (round d :: Int) ++ " km"

-- | Show bearing result
showBearing :: Angle -> String
showBearing (Angle a) = show (round a :: Int) ++ "°"

-- | Show area result
showArea :: Double -> String
showArea a = show (round a :: Int) ++ " km²"
