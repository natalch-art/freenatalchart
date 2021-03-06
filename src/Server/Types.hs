{-# LANGUAGE MultiParamTypeClasses #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}

{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}


module Server.Types where

import Import
    (($),
      Eq,
      Monad((>>=)),
      Read,
      Show(..),
      Semigroup((<>)),
      Maybe(..),
      Either(..),
      String,
      (.),
      Text,
      maybe,
      flip,
      readMaybe,
      NonEmpty,
      ReaderT,
      mkDay,
      mkDayPart,
      mkHour,
      mkMinute,
      mkMonth,
      mkYear,
      AppContext,
      Day(..),
      DayPart(unDayPart),
      Hour(..),
      Minute(..),
      Month(..),
      Year(..) )
import Servant
    (MimeRender(..), PlainText,  Handler,
      Header,
      type (:<|>),
      Headers,
      Lenient,
      Required,
      type (:>),
      Get,
      Raw,
      FromHttpApiData(parseUrlPiece),
      ToHttpApiData(toUrlPiece),
      QueryParam' )
import Servant.HTML.Lucid ( HTML )
import Lucid.Base (relaxHtmlT, ToHtml(..), Html)
import Validation (Validation)
import RIO.Text (pack)
import Ephemeris.Types
    ( Latitude(unLatitude),
      Longitude(unLongitude),
      mkLatitude,
      mkLongitude )
import RIO.Time (UTCTime)

type Param' = QueryParam' '[Required, Lenient]

type Service = 
    Get '[HTML] (Headers '[Header "Cache-Control" Text] (Html ()))
    :<|> "about" :> Get '[HTML]  (Headers '[Header "Cache-Control" Text] (Html ()))
    :<|> "full-chart" 
        :> Param' "location" Text
        :> Param' "day" Day
        :> Param' "month" Month
        :> Param' "year" Year
        :> Param' "hour" Hour
        :> Param' "minute" Minute
        :> Param' "day-part" DayPart
        :> Param' "lat" Latitude
        :> Param' "lng" Longitude
        :> Get '[HTML, PlainText] (Cached TextDocument)
    :<|> "transits" 
        :> Param' "at" UTCTime
        :> Param' "location" Text
        :> Param' "day" Day
        :> Param' "month" Month
        :> Param' "year" Year
        :> Param' "hour" Hour
        :> Param' "minute" Minute
        :> Param' "day-part" DayPart
        :> Param' "lat" Latitude
        :> Param' "lng" Longitude
        :> Get '[HTML, PlainText] (Cached TextDocument)
    :<|> Raw

type AppM = ReaderT AppContext Servant.Handler

type Cached a = Headers '[Header "Cache-Control" Text] a
type CachedHtml = Cached (Html ())

data TextDocument = 
    TextDocument {
        asHtml :: Html ()
    ,   asText :: Text
    } 

instance ToHtml TextDocument where
    toHtml = relaxHtmlT . asHtml
    toHtmlRaw = relaxHtmlT . asHtml

instance MimeRender PlainText TextDocument where
    mimeRender proxy val = mimeRender proxy $ asText val

-- Form types:

data ChartFormValidationError 
    = InvalidLocation
    | InvalidDateTime
    | InvalidYear
    | InvalidMonth
    | InvalidDay
    | InvalidHour
    | InvalidMinute
    | InvalidDayPart
    deriving (Eq, Show)

type ChartFormErrors = NonEmpty (ChartFormValidationError, Text)
type ChartFormValidation a = Validation ChartFormErrors a
type ParsedParameter a = Either Text a

data ChartForm = ChartForm
    {
        formLocation :: ParsedParameter Text
    ,   formLatitude :: ParsedParameter Latitude
    ,   formLongitude :: ParsedParameter Longitude
    ,   formYear :: ParsedParameter Year
    ,   formMonth :: ParsedParameter Month
    ,   formDay :: ParsedParameter Day
    ,   formHour :: ParsedParameter Hour
    ,   formMinute :: ParsedParameter Minute
    ,   formDayPart :: ParsedParameter DayPart
    } deriving (Eq, Show)

data FailedChartForm = FailedChartForm
    {
        originalForm :: ChartForm
    ,   validationErrors :: ChartFormErrors
    } deriving (Eq, Show)

-- orphan instances that only apply to the API

tryParse :: Read a => (a -> Maybe b) -> (Text -> Text) -> String -> Either Text b
tryParse constructor errMsg s =
    maybe (Left $ errMsg $ pack s)
          Right
          (readMaybe s >>= constructor)

prepend :: Text -> Text -> Text
prepend = flip (<>)

parseBounded :: Read a => (a -> Maybe b) -> Text -> Text -> Either Text b
parseBounded ctr err a=
    parseUrlPiece a >>= tryParse ctr (prepend err)

-- inspired by: https://github.com/haskell-servant/servant/issues/796
-- this year range is for the only years between which we have ephemerides data;
-- astro.com offers larger files for wider ranges, but we're good with
-- these for now. Don't pretend you know Jesus's birth time!
instance FromHttpApiData Year where
    parseUrlPiece = parseBounded mkYear " is not a valid year (we only have astronomical data for the years 1800 AD to 2399 AD.)" 

instance ToHttpApiData Year where
    toUrlPiece (Year v) = pack $ show v

instance FromHttpApiData Month where
    parseUrlPiece = parseBounded mkMonth " is not a valid month."

instance ToHttpApiData Month where
    toUrlPiece (Month m) = pack $ show m

instance FromHttpApiData Day where
    parseUrlPiece = parseBounded mkDay " is not a valid day of the month."

instance ToHttpApiData Day where
    toUrlPiece (Day d) = pack $ show d

instance FromHttpApiData Hour where
    parseUrlPiece = parseBounded mkHour " is not a valid hour (use 1-12)."

instance ToHttpApiData Hour where
    toUrlPiece (Hour h) = pack $ show h

instance FromHttpApiData Minute where
    parseUrlPiece = parseBounded mkMinute " is not a valid minute."

instance ToHttpApiData Minute where
    toUrlPiece (Minute m) = pack $ show m

instance FromHttpApiData DayPart where
    parseUrlPiece a = do 
        s <- parseUrlPiece a
        let parsed = mkDayPart s
        case parsed of
            Nothing -> Left $ pack s <> " Please choose a part of day (AM or PM)"
            Just d  -> Right d

instance ToHttpApiData DayPart where
    toUrlPiece = pack . unDayPart 

instance FromHttpApiData Latitude where
    parseUrlPiece = parseBounded mkLatitude " is not a valid latitude."

instance ToHttpApiData Latitude where
    toUrlPiece = pack . show . unLatitude

instance FromHttpApiData Longitude where
    parseUrlPiece = parseBounded mkLongitude " is not a valid longitude."

instance ToHttpApiData Longitude where
    toUrlPiece = pack . show . unLongitude
