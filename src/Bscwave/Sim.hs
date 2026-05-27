{-# LANGUAGE TupleSections #-}
module Bscwave.Sim where
import Data.IORef
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Foreign
import Foreign.C
import Data.Bits
import Bscwave.FFI

data Port = Port { portName :: String, portWidth :: Int, portRef :: IORef Integer }
data Sim  = Sim  { simInputs :: Map String Port, simOutputs :: Map String Port
                 , simStep :: IO (), simDestroy :: IO () }

input :: Sim -> String -> IORef Integer
input sim k = portRef (simInputs sim Map.! k)

nw :: Int -> Int
nw w = (w + 31) `div` 32

toWords :: Int -> Integer -> [Word32]
toWords w v = [fromIntegral (v `shiftR` (32*i)) .&. 0xffffffff | i <- [0..nw w - 1]]

fromWords :: [Word32] -> Integer
fromWords = foldl (\acc (i,w) -> acc .|. fromIntegral w `shiftL` (32*i)) 0 . zip [0..]

setPort :: Ptr () -> String -> Int -> Integer -> IO ()
setPort m name w val = withCString name $ \cn ->
  withArray (toWords w val) $ \buf -> bsim_set_param m cn buf (fromIntegral (nw w)) >> pure ()

getPort :: Ptr () -> String -> Int -> IO Integer
getPort m name w = withCString name $ \cn ->
  allocaArray n $ \buf -> bsim_get_result m cn buf (fromIntegral n) >> fromWords <$> peekArray n buf
  where n = nw w

mkPortRef :: (String, Int) -> IO Port
mkPortRef (name, w) = Port name w <$> newIORef 0

create :: [(String,Int)] -> [(String,Int)] -> IO Sim
create inPorts outPorts = do
  m    <- bsim_create 0 nullPtr
  ins  <- Map.fromList <$> mapM (\p@(n,_) -> (n,) <$> mkPortRef p) inPorts
  outs <- Map.fromList <$> mapM (\p@(n,_) -> (n,) <$> mkPortRef p) outPorts
  let step = do
        mapM_ (\(n,p) -> readIORef (portRef p) >>= setPort m n (portWidth p)) (Map.toList ins)
        mapM_ (\(n,p) -> getPort m n (portWidth p) >>= writeIORef (portRef p)) (Map.toList outs)
        withCString "CLK" (bsim_clock_posedge m) >> withCString "CLK" (bsim_clock_negedge m)
  pure $ Sim ins outs step (bsim_destroy m)

