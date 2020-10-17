{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE NoImplicitPrelude #-}

module Views.Chart (render, renderTestChartPage) where

import Chart.Calculations
import Chart.Graphics (renderChart)
import Data.Time.LocalTime.TimeZone.Detect (withTimeZoneDatabase)
import qualified Graphics.Svg as Svg
import Import hiding (for_)
import Lucid
import RIO.Text (pack)
import RIO.Time (rfc822DateFormat, formatTime, LocalTime, defaultTimeLocale, parseTimeM)
import SwissEphemeris (ZodiacSignName(..), LongitudeComponents (..), Planet (..))
import Views.Common
import Views.Chart.Explanations 

render :: BirthData -> HoroscopeData -> Html ()
render BirthData {..} h@HoroscopeData {..} = html_ $ do
  head_ $ do
    title_ "Your Natal Chart"
    metaCeremony
    style_ $ do
      "svg { height: auto; width: auto}\
      \.scrollable-container {overflow: auto !important;}\
      \"

  body_ $ do
    header_ [class_ "navbar bg-gray"] $ do
      section_ [class_ "navbar-section"] $ do
        a_ [href_ "#chart", class_ "navbar-brand text-bold mr-2"] "Your Free Natal Chart"
      section_ [class_ "navbar-section"] $ do
        a_ [href_ "/", class_ "btn btn-link"] "Start Over"
        a_ [href_ "https://github.com/lfborjas/freenatalchart.xyz/issues"
           , class_ "btn btn-link text-error"
           , target_ "_blank"] $ do
          "Report an issue"
    div_ [id_ "main", class_ "container grid-xl mx-4"] $ do
      div_ [class_ ""] $ do
        -- p_ [class_ "text-muted text-small"] $ do
        --   "To learn more about each component of your chart, you can click on the zodiac signs, the houses, or the planets."
        --   " We encourage you to take the descriptions presented here to find your own meaning from what the chart presents! "
        --   " You can also just scroll down to the "
        --   a_ [href_ "#signs"] "Zodiac Signs"
        --   " section and follow the links between all components!"

        figure_ [id_ "chart", class_ "figure p-centered my-2", style_ "max-width: 600px;"] $ do
          div_ [] $ do
            -- unfortunately, the underlying library assigns `height` and `width` attributes to the SVG:
            -- https://github.com/circuithub/diagrams-svg/blob/master/src/Graphics/Rendering/SVG.hs#L92-L93
            -- and any attempt to replace them simply prepends or appends instead:
            -- https://hackage.haskell.org/package/svg-builder-0.1.1/docs/src/Graphics.Svg.Core.html#with
            -- so instead we simply set them to invalid strings (sorry console sleuths,)
            -- and then set the attributes via CSS, since that's allowed (they're Geometry Properties:)
            -- https://developer.mozilla.org/en-US/docs/Web/SVG/Attribute/height#svg
            (toHtmlRaw $ Svg.renderBS $ renderChart [Svg.makeAttribute "height" "not", Svg.makeAttribute "width" "not"] 600 h)

          div_ [class_ "tile tile-centered text-center"] $ do
            div_ [class_ "tile-icon"] $ do
              div_ [class_ "px-2"] $ do
                maybe mempty asIcon sunSign
                br_ []
                span_ [class_ "text-tiny", title_ "Sun Sign"] "Sun"
            div_ [class_ "tile-content"] $ do
              div_ [class_ "tile-title text-dark"] $ do
                toHtml $ birthLocation & locationInput
                "  ·  "
                toHtml $ birthLocalTime & formatTime defaultTimeLocale rfc822DateFormat
              small_ [class_ "tile-subtitle text-gray"] $ do
                latLngHtml birthLocation
                "  ·  "
                toHtml $ horoscopeUniversalTime & formatTime defaultTimeLocale "%Y-%m-%d %H:%M:%S %Z"
            div_ [class_ "tile-action"] $ do
              div_ [class_ "px-2"] $ do
                maybe mempty asIcon asc
                br_ []
                span_ [class_ "text-tiny", title_ "Ascendant"] "Asc"

        details_ [id_ "planet-positions", class_ "accordion my-2", open_ ""] $ do
          summary_ [class_ "accordion-header bg-secondary"] $ do
            headerIcon
            sectionHeading $ do
              "Planet Positions"

          div_ [class_ "accordion-body scrollable-container"] $ do
            table_ [class_ "table table-striped table-hover"] $ do
              thead_ [] $ do
                tr_ [] $ do
                  th_ [] "Planet"
                  th_ [] "House"
                  th_ [] "Longitude"
                  th_ [] "Latitude"
                  th_ [] "Speed"
                  th_ [] "Declination"
              tbody_ [] $ do
                forM_ (horoscopePlanetPositions) $ \pp@PlanetPosition {..} -> do
                  tr_ [] $ do
                    td_ $ do
                      asIcon planetName
                      planetLabel planetName
                      if isRetrograde pp then "(r)" else ""

                    td_ $ do
                      housePositionHtml $ housePosition horoscopeHouses planetLng

                    td_ $ do
                      htmlDegreesZodiac planetLng

                    td_ $ do
                      htmlDegreesLatitude planetLat

                    td_ $ do
                      htmlDegrees planetLngSpeed

                    td_ $ do
                      htmlDegreesLatitude $ Latitude planetDeclination

        details_ [id_ "house-cusps", class_ "accordion my-2", open_ ""] $ do
          summary_ [class_ "accordion-header bg-secondary"] $ do
            headerIcon
            sectionHeading "House Cusps"
          div_ [class_ "accordion-body scrollable-container"] $ do
            p_ $ do
              "System Used: "
              mark_ $ toHtml $ toText horoscopeSystem
              " (to learn more about house systems and the meaning of each house, see the "
              a_ [href_ "#houses"] "Houses"
              " section.)"
            table_ [class_ "table table-striped table-hover"] $ do
              thead_ [] $ do
                tr_ [] $ do
                  th_ [] "House"
                  th_ [] "Cusp"
                  th_ [] "Declination"
              tbody_ [] $ do
                forM_ (horoscopeHouses) $ \hc@House {..} -> do
                  tr_ [] $ do
                    td_ $ do
                      housePositionHtml (Just hc)
                      houseLabel houseNumber
                    td_ $ do
                      htmlDegreesZodiac houseCusp
                    td_ $ do
                      htmlDegreesLatitude $ Latitude houseDeclination

        details_ [id_ "aspects-summary", class_ "accordion my-2", open_ ""] $ do
          summary_ [class_ "accordion-header bg-secondary"] $ do
            headerIcon
            sectionHeading "Aspects Summary"
          div_ [class_ "accordion-body"] $ do
            p_ $ do
              "For more detailed descriptions of aspects, see the "
              a_ [href_ "#aspects"] "Aspects"
              " section."
            table_ [class_ "table table-scroll table-hover"] $ do
              forM_ defaultPlanets $ \rowPlanet -> do
                tr_ [] $ do
                  td_ [] $ do
                    if rowPlanet == Sun
                      then mempty
                      else asIcon rowPlanet
                  forM_ (takeWhile (not . (== rowPlanet) . planetName) horoscopePlanetPositions) $ \PlanetPosition {..} -> do
                    td_ [style_ "border: 1px solid", class_ "text-small"] $ do
                      aspectCell $ findAspectBetweenPlanets horoscopePlanetaryAspects rowPlanet planetName
                  td_ [style_ "border-bottom: 1px solid"] $ do
                    asIcon rowPlanet
              tr_ [] $ do
                td_ [] $ do
                  span_ [class_ "tooltip", data_ "tooltip" "Ascendant"] "AC"
                forM_ (horoscopePlanetPositions) $ \PlanetPosition {..} -> do
                  td_ [style_ "border: 1px solid", class_ "text-small"] $ do
                    aspectCell $ findAspectWithAngle horoscopeAngleAspects planetName I
              tr_ [] $ do
                td_ [] $ do
                  span_ [class_ "tooltip", data_ "tooltip" "Midheaven"] "MC"
                forM_ (horoscopePlanetPositions) $ \PlanetPosition {..} -> do
                  td_ [style_ "border: 1px solid", class_ "text-small"] $ do
                    aspectCell $ findAspectWithAngle horoscopeAngleAspects planetName X

        details_ [id_ "orbs-used", class_ "accordion my-2"] $ do
          summary_ [class_ "accordion-header bg-gray"] $ do
            headerIcon
            sectionHeading "Orbs used"
          div_ [class_ "accordion-body scrollable-container"] $ do
            table_ [class_ "table table-striped table-hover"] $ do
              thead_ [] $ do
                tr_ [] $ do
                  th_ "Aspect"
                  th_ "Angle"
                  th_ "Orb"
              tbody_ [] $ do
                forM_ (majorAspects <> minorAspects) $ \Aspect {..} -> do
                  tr_ [] $ do
                    td_ $ do
                      asIcon aspectName
                      " "
                      toHtml $ toText aspectName
                    td_ $ do
                      toHtml $ toText angle
                    td_ $ do
                      toHtml $ toText maxOrb

        details_ [id_ "signs", class_ "accordion my-2", open_ ""] $ do
          summary_ [class_ "accordion-header bg-secondary"] $ do
            headerIcon
            sectionHeading "Zodiac Signs"
          
          div_ [] $ do
            generalSignsExplanation
            forM_ [Aries .. Pisces] $ \zodiacSign -> do
              h4_ [id_ $ toText zodiacSign] $ do
                asIcon zodiacSign
                " "
                toHtml . toText $ zodiacSign
              backToChart
              
              explain zodiacSign
              let
                planets' = planetsInSign' zodiacSign
                in do
                    h5_ "Planets Contained: "
                    if null planets' then
                      p_ $ do
                        em_ "Your chart doesn't have any planets in this sign."
                    else
                      ul_ [] $ do
                        forM_ planets' $ \p -> do
                          li_ $ do
                            planetDetails p
              let
                houses' = housesInSign' zodiacSign
                in do
                    h5_ "House cusps contained: "
                    if null houses' then
                      p_ $ do
                        em_ "Your chart doesn't have any house cusps in this sign."
                    else
                      ul_ [] $ do
                        forM_ houses' $ \hs -> do
                          li_ $ do
                            houseDetails hs

        details_ [id_ "houses", class_ "accordion my-2", open_ ""] $ do
          summary_ [class_ "accordion-header bg-secondary"] $ do
            headerIcon
            sectionHeading "Houses"
          div_ [] $ do
            generalHousesExplanation
            forM_ horoscopeHouses $ \huis@House{..} -> do
              h4_ [id_ $ "house-" <> toText houseNumber] $ do
                toHtml $ "House " <> (toText houseNumber)
              backToChart
              p_ [] $ do
                b_ "Starts at: "
                zodiacLink huis
              explain houseNumber

              let
                planets'  = planetsInHouse' huis
                in do
                  h5_ "Planets contained: "
                  if null planets' then
                    p_ $ do
                      em_ "Your chart doesn't have any planets in this house."
                  else
                    ul_ [] $ do
                      forM_ planets' $ \p -> do
                        li_ $ do
                          planetDetails p

        details_ [id_ "planets", class_ "accordion my-2", open_ ""] $ do
          summary_ [class_ "accordion-header bg-secondary"] $ do
            headerIcon
            sectionHeading "Planets"

          div_ [] $ do
            generalPlanetsExplanation
            forM_ horoscopePlanetPositions $ \p -> do
              h4_ [id_ $ pack . label . planetName $ p] $ do
                asIcon . planetName $ p
                " "
                toHtml . label . planetName $ p
              backToChart
              p_ [] $ do
                b_ "Located in: "
                zodiacLink . planetLng $ p
                if (isRetrograde p) then
                  b_ "(retrograde)"
                else
                  mempty
              p_ [] $ do
                b_ "House: "
                maybe mempty houseDetails (housePosition' . planetLng $ p)

              explain . planetName $ p

              let
                aspects' = p & planetName & aspectsForPlanet' & catMaybes
                axes'    = p & planetName & axesAspectsForPlanet' & catMaybes
                in do
                  h5_ "Aspects: "
                  if (null aspects' && null axes') then
                    p_ $ do
                      em_ "This planet is unaspected. Note that not having any aspects is rare, which means this planet's sole influence can be quite significant."
                  else
                    aspectsList aspects' axes'


        details_ [id_ "aspects", class_ "accordion my-2", open_ ""] $ do
          summary_ [class_ "accordion-header bg-secondary"] $ do
            headerIcon
            sectionHeading "Aspects"

          div_ [] $ do
            generalAspectsExplanation

            h4_ "Major Aspects: "
            forM_ majorAspects $ \a -> do
              aspectDetails' a 

            h4_ "Minor Aspects: "
            forM_ minorAspects $ \a -> do
              aspectDetails' a

        details_ [id_ "references", class_ "accordion my-2"] $ do
          summary_ [class_ "accordion-header bg-secondary"] $ do
            headerIcon
            sectionHeading "References"
          div_ [class_ "accordion-body"] $ do
            attribution
              

    -- the SVG font for all icons.
    -- TODO: path is wrong for server-rendered!
    --link_ [rel_ "stylesheet", href_ "static/css/freenatalchart-icons.css"]
    link_ [rel_ "stylesheet", href_ "/css/freenatalchart-icons.css"]
    link_ [rel_ "stylesheet", href_ "https://unpkg.com/spectre.css/dist/spectre-icons.min.css"]
    footer_ [class_ "navbar bg-secondary"] $ do
      section_ [class_ "navbar-section"] $ do
        a_ [href_ "/about", class_ "btn btn-link", title_ "tl;dr: we won't sell you anything, or store your data."] "About"
      section_ [class_ "navbar-center"] $ do
        -- TODO: add a lil' icon?
        span_ "Brought to you by a ♑"
      section_ [class_ "navbar-section"] $ do
        a_ [href_ "https://github.com/lfborjas/freenatalchart.xyz", title_ "Made in Haskell with love and a bit of insanity.", class_ "btn btn-link"] "Source Code"
  where
    -- markup helpers
    headerIcon = i_ [class_ "icon icon-arrow-right mr-1 c-hand"] ""
    sectionHeading = h3_ [class_ "d-inline"]
    sunSign = (findSunSign horoscopePlanetPositions)
    asc = (findAscendant horoscopeHouses)
    planetsByHouse' = planetsByHouse horoscopeHouses horoscopePlanetPositions
    planetsInHouse' = planetsInHouse planetsByHouse'
    planetsBySign'  = planetsBySign horoscopePlanetPositions
    planetsInSign'  = planetsInSign planetsBySign'
    housesBySign'   = housesBySign horoscopeHouses
    housesInSign'   = housesInSign housesBySign'
    housePosition'  = housePosition horoscopeHouses
    aspectsForPlanet' p = map (findAspectBetweenPlanets horoscopePlanetaryAspects p) [Sun .. Chiron]
    axesAspectsForPlanet' p = map (findAspectWithAngle horoscopeAngleAspects p)  [I, X]
    aspectDetails' = aspectDetails horoscopePlanetaryAspects horoscopeAngleAspects


aspectDetails :: [HoroscopeAspect PlanetPosition PlanetPosition] -> [HoroscopeAspect PlanetPosition House] -> Aspect -> Html ()
aspectDetails allPlanetAspects allAxesAspects Aspect {..} = do
  h5_ [id_ $ toText aspectName] $ do
    asIcon aspectName
    " "
    toHtml . toText $ aspectName
  backToChart
  dl_ $ do
    dt_ "Classification"
    dd_ . toHtml . toText $ aspectType
    dt_ "Temperament"
    dd_ . toHtml . toText $ temperament
    dt_ "Traditional color"
    dd_ . toHtml . aspectColor $ temperament
    dt_ "Angle"
    dd_ . toHtml . toText $ angle
    dt_ "Orb used"
    dd_ . toHtml . toText $ maxOrb
  p_ [] $ do
    explain aspectName  
  h6_ . toHtml $ (toText aspectName) <> "s in your chart:"  
  if (null planetAspects && null axesAspects) then
    em_ . toHtml $ "No " <> (toText aspectName) <> "s appear in your chart."
  else
    aspectsList planetAspects axesAspects
  where
    planetAspects = findAspectsByName allPlanetAspects aspectName
    axesAspects   = findAspectsByName allAxesAspects aspectName

aspectsList :: [HoroscopeAspect PlanetPosition PlanetPosition] -> [HoroscopeAspect PlanetPosition House] -> Html ()
aspectsList aspects' axes'= do
  ul_ [] $ do
    forM_ aspects' $ \pa -> do
      li_ $ do
        planetAspectDetails pa  
    forM_ axes' $ \aa -> do
      li_ $ do
        axisAspectDetails aa

planetAspectDetails :: (HoroscopeAspect PlanetPosition PlanetPosition) -> Html ()
planetAspectDetails HoroscopeAspect{..} = do
  span_ [aspectColorStyle aspect] $ do
    bodies & fst & planetName & asIcon
    aspect & aspectName & asIcon
    bodies & snd & planetName & asIcon
  " — "
  bodies & fst & planetName & planetLink
  " "
  strong_ $ aspect & aspectName & aspectLink
  " "
  bodies & snd & planetName & planetLink
  "; orb: "
  htmlDegrees' (True, True) orb

axisAspectDetails :: (HoroscopeAspect PlanetPosition House) -> Html ()
axisAspectDetails HoroscopeAspect{..} = do
  span_ [aspectColorStyle aspect] $ do
    bodies & fst & planetName & asIcon
    aspect & aspectName & asIcon
    bodies & snd & houseNumber & houseLabel
  " — "
  bodies & fst & planetName & planetLink
  " "
  strong_ $ aspect & aspectName & aspectLink
  " "
  bodies & snd & houseNumber & houseLink
  "; orb: "
  htmlDegrees' (True, True) orb

planetDetails :: PlanetPosition -> Html ()
planetDetails PlanetPosition{..} = 
  span_ [] $ do
    asIcon planetName
    a_ [href_ $ "#" <> (pack . label) planetName] $ do
      planetLabel planetName
    " — located in: "
    zodiacLink planetLng

houseDetails :: House -> Html ()
houseDetails House{..} =
  span_ [] $ do
    a_ [href_ $ "#house-" <> toText houseNumber] $ do
      toHtml $ "House " <> toText houseNumber
      houseLabel houseNumber
    " — starting at: "
    zodiacLink houseCusp

asIcon :: HasLabel a => a -> Html ()
asIcon z =
  i_ [class_ ("fnc-" <> shown <> " tooltip"), title_ shown, data_ "tooltip" label'] ""
  where
    label' = pack . label $ z
    shown  = toText z

htmlDegreesZodiac :: HasLongitude a => a -> Html ()
htmlDegreesZodiac p =
  abbr_ [title_ (pack . show $ pl)] $ do
    maybe mempty asIcon (split & longitudeZodiacSign)
    toHtml $ (" " <> (toText $ longitudeDegrees split)) <> "° "
    toHtml $ (toText $ longitudeMinutes split) <> "\' "
    toHtml $ (toText $ longitudeSeconds split) <> "\""
  where
    pl = getLongitudeRaw p
    split = splitDegreesZodiac pl

htmlDegreesLatitude :: Latitude -> Html ()
htmlDegreesLatitude l =
  abbr_ [title_ (pack . show $ l)] $ do
    toHtml $ (toText $ longitudeDegrees split) <> "° "
    toHtml $ (toText $ longitudeMinutes split) <> "\' "
    toHtml $ (toText $ longitudeSeconds split) <> "\" "
    toHtml direction
  where
    split = splitDegrees $ unLatitude l
    direction :: Text
    direction = if (unLatitude l) < 0 then "S" else "N"

htmlDegrees :: Double -> Html ()
htmlDegrees = htmlDegrees' (True, True)

htmlDegrees' :: (Bool, Bool) -> Double -> Html ()
htmlDegrees' (includeMinutes, includeSeconds) l =
  abbr_ [title_ (pack . show $ l)] $ do
    toHtml sign
    toHtml $ (toText $ longitudeDegrees split) <> "° "
    if includeMinutes then
      toHtml $ (toText $ longitudeMinutes split) <> "\' "
    else
      mempty
    if includeSeconds then
      toHtml $ (toText $ longitudeSeconds split) <> "\""
    else
      mempty
  where
    split = splitDegrees l
    sign :: Text
    sign = if l < 0 then "-" else ""

-- TODO: this is just htmlDegrees with a hat!
zodiacLink :: HasLongitude a => a -> Html ()
zodiacLink p =
  a_  [href_ $ "#" <> link'] $ do
    maybe mempty asIcon (split & longitudeZodiacSign)
    toHtml $ (" " <> (toText $ longitudeDegrees split)) <> "° "
    toHtml $ (toText $ longitudeMinutes split) <> "\' "
    toHtml $ (toText $ longitudeSeconds split) <> "\""
  where
    link' = maybe "chart" toText (split & longitudeZodiacSign)
    pl = getLongitudeRaw p
    split = splitDegreesZodiac pl  

planetLink :: Planet -> Html ()
planetLink p =
  a_ [href_ $ "#" <> textLabel] $ do
    toHtml textLabel
  where
    textLabel = p & label & pack

houseLink :: HouseNumber -> Html ()
houseLink h =
  a_ [href_ $ "#house-" <> textLabel] $ do
    houseToAxis h
  where
    textLabel = h & label & pack
  
aspectLink :: AspectName -> Html ()
aspectLink a =
  a_ [href_ $ "#" <> textLabel] $ do
    toHtml textLabel
  where
    textLabel = a & toText

backToChart :: Html  ()
backToChart =
  p_ [] $ do
    a_ [href_ "#chart"] "(Back to chart)" 

housePositionHtml :: Maybe House -> Html ()
housePositionHtml Nothing = mempty
housePositionHtml (Just House {..}) =
  toHtml . toText . (+ 1) . fromEnum $ houseNumber

planetLabel :: Planet -> Html ()
planetLabel MeanNode = toHtml (" Mean Node" :: Text)
planetLabel MeanApog = toHtml (" Lilith" :: Text)
planetLabel p = toHtml . (" " <>) . toText $ p

houseLabel :: HouseNumber -> Html ()
houseLabel I = toHtml (" (Asc)" :: Text)
houseLabel IV = toHtml (" (IC)" :: Text)
houseLabel VII = toHtml (" (Desc)" :: Text)
houseLabel X = toHtml (" (MC)" :: Text)
houseLabel _ = mempty

houseToAxis :: HouseNumber -> Html ()
houseToAxis I = toHtml ("Ascendant"::Text)
houseToAxis X = toHtml ("Midheaven"::Text)
houseToAxis _ = mempty

aspectCell :: Maybe (HoroscopeAspect a b) -> Html ()
aspectCell Nothing = mempty
aspectCell (Just HoroscopeAspect {..}) =
  span_ [aspectColorStyle aspect] $ do
    asIcon . aspectName $ aspect
    " "
    htmlDegrees' (True, False) orb

aspectColor :: AspectTemperament -> Text
aspectColor Analytical = "red"
aspectColor Synthetic = "blue"
aspectColor Neutral = "green"

aspectColorStyle :: Aspect -> Attribute
aspectColorStyle aspect = style_ ("color: " <> (aspectColor . temperament $ aspect))

latLngHtml :: Location -> Html ()
latLngHtml Location {..} =
  toHtml $ " (" <> lnText <> ", " <> ltText <> ")"
  where
    lnSplit = splitDegrees . unLongitude $ locationLongitude
    lnText = pack $ (show $ longitudeDegrees lnSplit) <> (if locationLongitude > 0 then "e" else "w") <> (show $ longitudeMinutes lnSplit)
    ltSplit = splitDegrees . unLatitude $ locationLatitude
    ltText = pack $ (show $ longitudeDegrees ltSplit) <> (if locationLatitude > 0 then "n" else "s") <> (show $ longitudeMinutes ltSplit)

toText :: Show a => a -> Text
toText = pack . show

renderTestChartPage :: IO ()
renderTestChartPage = do
  ephe <- pure $ "./config"
  withTimeZoneDatabase "./config/timezone21.bin" $ \db -> do
    birthplace <- pure $ Location "Tegucigalpa" (Latitude 14.0839053) (Longitude $ -87.2750137)
    birthtime <- parseTimeM True defaultTimeLocale "%Y-%-m-%-d %T" "1989-01-06 00:30:00" :: IO LocalTime
    let birthdata = BirthData birthplace birthtime
    calculations <- horoscope db ephe birthdata
    renderToFile "test-chart.html" $ render birthdata calculations
