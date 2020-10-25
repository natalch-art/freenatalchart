module TestUtil where

import Test.Hspec.Golden ( Golden(..) )
import RIO.Text.Lazy (unpack)
import qualified Lucid.Base as L
import RIO.ByteString (ByteString)
import qualified RIO.Text as T
import qualified RIO.ByteString.Lazy as LB

goldenFixture :: String -> String -> Golden String
goldenFixture name output_ =
  Golden {
    output = output_
  , encodePretty = show
  , testName = name
  , writeToFile = writeFile
  , readFromFile = readFile
  , directory = "test/files"
  , failFirstTime = False
  }

renderHtmlToString :: L.Html a -> String
renderHtmlToString = unpack . L.renderText

testTzDB :: FilePath
testTzDB = "./config/timezone21.bin"

testEphe :: FilePath
testEphe = "./config"

-- from: https://github.com/hspec/hspec-wai/blob/22e244faee3942da56e7499550b9e7ed61d3f937/src/Test/Hspec/Wai/Util.hs#L29
safeToString :: ByteString -> Maybe String
safeToString bs = do
  str <- either (const Nothing) (Just . T.unpack) (T.decodeUtf8' bs)
  return str
  -- let isSafe = not $ case str of
  --       [] -> True
  --       _  -> isSpace (last str) || any (not . isPrint) str
  -- guard isSafe >> return str

-- for compatibility with older versions of `bytestring`
toStrict :: LB.ByteString -> ByteString
toStrict = mconcat . LB.toChunks
