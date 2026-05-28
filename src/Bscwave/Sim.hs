{-# LANGUAGE DataKinds #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
module Bscwave.Sim
  ( Sim (..)
  , create
  ) where

import Data.IORef
import Foreign
import Foreign.C
import Data.Bits (shiftR, (.&.), (.|.), shiftL)
import GHC.TypeLits (KnownNat)

import Bscwave.FFI
import Bscwave.Interface

-- | A live simulator. @i@ and @o@ are the input and output port records
-- (each a higher-kinded record of 'Port').
data Sim i o = Sim
  { inputs     :: i Port
  , outputs    :: o Port
  , simStep    :: IO ()
  , simDestroy :: IO ()
  }

nw :: Int -> Int
nw w = (w + 31) `div` 32

toWords :: Int -> Integer -> [Word32]
toWords w v = [fromIntegral (v `shiftR` (32*i)) .&. 0xffffffff | i <- [0 .. nw w - 1]]

fromWords :: [Word32] -> Integer
fromWords = foldl (\acc (i,w) -> acc .|. fromIntegral w `shiftL` (32*i)) 0 . zip [0 :: Int ..]

setPort :: Ptr () -> String -> Int -> Integer -> IO ()
setPort m name w val = withCString name $ \cn ->
  withArray (toWords w val) $ \buf ->
    bsim_set_param m cn buf (fromIntegral (nw w)) >> pure ()

getPort :: Ptr () -> String -> Int -> IO Integer
getPort m name w = withCString name $ \cn ->
  allocaArray n $ \buf ->
    bsim_get_result m cn buf (fromIntegral n) >> fromWords <$> peekArray n buf
  where n = nw w

mkPort :: forall n. KnownNat n => String -> IO (Port n)
mkPort name = do
  ref <- newIORef 0
  fmt <- newIORef (defaultFormat @n)
  pure (Port name ref fmt)

create
  :: forall i o. (Interface i, Interface o)
  => String -> IO (Sim i o)
create modelName = do
  m   <- withCString modelName bsim_create
  ins  <- mkInterface @i mkPort
  outs <- mkInterface @o mkPort
  let pushIn  = traverseI_ (\n p -> readIORef (portRef p) >>= setPort m n (portWidth p)) ins
      pullOut = traverseI_ (\n p -> getPort m n (portWidth p) >>= writeIORef (portRef p)) outs
      step = do
        pushIn
        pullOut
        withCString "CLK" (bsim_clock_posedge m)
        withCString "CLK" (bsim_clock_negedge m)
  pure $ Sim ins outs step (bsim_destroy m)
