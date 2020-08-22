{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE NoMonomorphismRestriction #-}
{-# LANGUAGE FlexibleContexts, TypeFamilies #-}

module Chart where

import Import hiding ((^.), local, over)
import Diagrams.Prelude
import Diagrams.Backend.SVG
import RIO.List.Partial ((!!))
import Diagrams.TwoD.Vector (e)
import Diagrams.Core.Types (keyVal)
import Calculations (mkCoordinates, mkTime, horoscope, angularDifference, rotateList)
import Control.Category ((<<<))
import Prerendered as P
import SwissEphemeris (closeEphemerides, setEphemeridesPath, Planet(..))
import Prelude (putStrLn)

--signColor :: (Ord a, Floating a) => ZodiacSign -> Colour a
signColor :: ZodiacSign -> Colour Double
signColor (ZodiacSign _ _ zElement) =
    case zElement of
        Import.Earth -> darkgreen
        Air -> yellow
        Fire -> red
        Water -> lightblue


--zodiacBand :: (TrailLike (QDiagram b V2 Longitude m), Semigroup m) => ZodiacSign -> QDiagram b V2 Longitude m
zodiacBand sign@(ZodiacSign signName zLng _) = 
    g <> w # fc (signColor sign)
           # lw thin
           # (href $ "/explanations#zodiac-" <> (show signName))
           -- can set `title`, `id` or `class`:
           -- https://hackage.haskell.org/package/diagrams-svg-1.4.3/docs/src/Diagrams.Backend.SVG.html
           # (keyVal $ ("title", show signName))
    where
        d :: Direction V2 Longitude
        d = rotateBy ((zLng @@ deg) ^. turn) xDir
        a :: Angle Double
        a = 30 @@ deg
        w = annularWedge 1 0.8 d a
        glyphPosition = longitudeToPoint 0.9 (zLng + 15)
        g = (stroke $ P.prerenderedSign signName)
            # scale 0.15
            # moveTo glyphPosition
            # rotateAround glyphPosition (-70 @@ deg)
            # fc black
            # lw thin

--zodiacCircle :: (Semigroup m, TrailLike (QDiagram b V2 Longitude m)) => QDiagram b V2 Longitude m
zodiacCircle = mconcat $ map zodiacBand westernZodiacSigns

cuspBand (House houseName cuspBegin, House _ cuspEnd) =
    t <> w # lw thin
           # lc gray
           # (href $ "/explanations#house-" <> (show houseName))
    where
        d = rotateBy ((cuspBegin @@ deg) ^. turn) xDir
        a = (angularDifference cuspBegin cuspEnd) @@ deg
        w = annularWedge 0.8 0.5 d a
        textPosition :: Point V2 Double
        textPosition = longitudeToPoint 0.55 (cuspBegin + 5)
        t = (text $ houseLabel houseName) 
            # moveTo textPosition
            # fontSize (local 0.05)
            # fc gray
            # rotateAround textPosition (-70 @@ deg)

houseLabel :: HouseNumber -> String
houseLabel = fromEnum >>> (+1) >>> show

ascendant :: [House] -> House
ascendant h =  h !! 0

mc :: [House] -> House
mc h = h !! 9

-- | Given a longitude and a magnitude (distance from origin)
-- return a point sitting at the equivalent vector
-- more on vectors:
-- https://archives.haskell.org/projects.haskell.org/diagrams/doc/vector.html#vector-operations
longitudeToPoint :: Double -> Longitude -> Point V2 Double
longitudeToPoint magnitude longitude = 
    origin .+^ v
    where
        theta = longitude @@ deg
        v = magnitude *^ e theta


--cuspsCircle :: (Semigroup m, TrailLike (QDiagram b V2 Longitude m)) => [House] -> QDiagram b V2 Longitude m
cuspsCircle c = 
    mconcat $ map cuspBand pairedC
    where
        pairedC = zip c $ rotateList 1 c


--quadrant :: (TrailLike (QDiagram b V2 Longitude m), Semigroup m) => (House, House) -> QDiagram b V2 Longitude m
quadrant (House houseName cuspBegin, House _ cuspEnd) =
    t <> w # lw thin
           # (href $ "/explanations#angle-" <> (show houseName))
    where 
        d = rotateBy ((cuspBegin @@ deg) ^. turn) xDir
        a = (angularDifference cuspBegin cuspEnd) @@ deg
        w = wedge 1 d a
        textPosition = longitudeToPoint 0.75 (cuspBegin + 4)
        t = (text $ quadrantLabel houseName) 
            # moveTo textPosition
            # fontSize (local 0.05)
            # fc black
            # rotateAround textPosition (-70 @@ deg)

quadrantLabel :: HouseNumber -> String
quadrantLabel I = "ASC"
quadrantLabel IV = "IC"
quadrantLabel VII = "DC"
quadrantLabel X = "MC"
quadrantLabel _ = ""

--quadrants :: (Semigroup m, TrailLike (QDiagram b V2 Longitude m)) => [House] -> QDiagram b V2 Longitude m
quadrants c = 
    mconcat $ map quadrant angles
    where
        angles = 
            [(c !! 0, c !! 3) -- AC
            ,(c !! 3, c !! 6) -- IC
            ,(c !! 6, c !! 9) -- DC
            ,(c !! 9, c !! 0) -- MC
            ]

aspectLine :: HoroscopeAspect PlanetPosition PlanetPosition -> Diagram B
aspectLine HoroscopeAspect{..} =
    aPos ~~ bPos # lc aspectColor
                 # lw thin
    where
        (aPos, bPos) = (over each) (longitudeToPoint 0.5 <<< getLongitude) bodies
        aspectColor = 
            case (temperament aspect) of
                Analytical -> red
                Synthetic -> blue
                Neutral -> green

aspects pAspects = mconcat $ map aspectLine pAspects

--drawPlanet :: PlanetPosition -> Diagram B
drawPlanet rectifyF pos@PlanetPosition{..} =
    (stroke $ P.prerenderedPlanet planetName)
    # scale 0.1
    # moveTo eclipticPosition
    # rectifyF eclipticPosition
    # fc black
    # lw ultraThin
    # (keyVal $ ("title", show planetName))
    # (href $ "#" <> (show planetName))
    <> guideLines
    where
        atEclipticPosition = flip longitudeToPoint $ getLongitude pos
        eclipticPosition = atEclipticPosition 0.65
        aspectCircleLine = atEclipticPosition 0.5 ~~ atEclipticPosition 0.53
        zodiacCircleLine = atEclipticPosition 0.8 ~~ atEclipticPosition 0.78
        guideLines = (aspectCircleLine <> zodiacCircleLine) # lw thin

-- TODO: group planets by latitude and lay them radially, vs. hoping they're not in the same latitude!
planets :: [PlanetPosition] -> (Point V2 Double -> Diagram B -> Diagram B ) -> Diagram B
planets planetPositions rectifyF = mconcat $ map (drawPlanet rectifyF) planetPositions

--chart :: (Semigroup m, TrailLike (QDiagram b V2 Longitude m)) => [House] -> QDiagram b V2 Longitude m
chart HoroscopeData{..} rectifyF = 
    zodiacCircle 
    <> planets horoscopePlanetPositions rectifyF
    <> cuspsCircle horoscopeHouses
    <> quadrants horoscopeHouses 
    <> aspects horoscopePlanetaryAspects
    -- TODO: horoscopeCelestialAspects?

-- TODO: probably need a reader monad context here (for pre-rendered things.)
-- also, need to return the diagram, not render to a file.
renderChart :: HoroscopeData -> IO ()
renderChart z@HoroscopeData{..}=
  renderSVG
    "circle.svg"
    (mkWidth 400)
    (chart z rectify # rotateBy (ascendantOffset ^. turn))
   where
       ascendantOffset =  (180 - ((houseCusp . ascendant) horoscopeHouses) @@ deg)
       rectify :: Point V2 Double -> Diagram B -> Diagram B 
       rectify p = rotateAround p $ negated ascendantOffset

renderTestChart :: IO ()
renderTestChart = do
    -- TODO: bring in the `directory` package?
    setEphemeridesPath "/Users/luis/code/lfborjas/cassiel/config"
    --let calculations = horoscope 2447532.771485 (mkCoordinates 14.0839053 (-87.2750137))
    let calculations = horoscope (mkTime 1989 1 6 0.0) (mkCoordinates 14.0839053 (-87.2750137))
    renderChart calculations
    closeEphemerides
