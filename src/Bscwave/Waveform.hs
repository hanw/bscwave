{-# LANGUAGE DataKinds #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
module Bscwave.Waveform
  ( WaveData (..)
  , Wave (..)
  , Waveform (..)
  , waveData
  , waveName
  , create
  ) where

import Data.IORef
import Bscwave.Sim (Sim (..))
import Bscwave.Interface

-- | A captured signal: bit width, the sample list, and the display
-- formatter snapshotted from the originating 'Port' at capture time.
data WaveData = WaveData
  { wdWidth   :: Int
  , wdSamples :: IORef [Integer]
  , wdFormat  :: Integer -> String
  }
data Wave     = Clock String | Binary String WaveData | WaveN String Int WaveData
data Waveform = Waveform { wfWaves :: [Wave] }

waveData :: Wave -> Maybe WaveData
waveData (Binary _ d)  = Just d
waveData (WaveN  _ _ d) = Just d
waveData _              = Nothing

waveName :: Wave -> String
waveName (Clock n)    = n
waveName (Binary n _) = n
waveName (WaveN n _ _) = n

-- | For each port, build a 'Wave' plus the IO action that snapshots its
-- current IORef value into the wave's sample list. The formatter is read
-- here (once) so post-capture mutations of @portFormat@ don't retroactively
-- change how earlier samples display.
collect :: Interface r => r Port -> IO [(Wave, IO ())]
collect rec = do
  acc <- newIORef []
  traverseI_ (\name port -> do
      let w = portWidth port
      samples <- newIORef []
      fmt     <- readIORef (portFormat port)
      let intFmt v = fmt (bit v)
          wd       = WaveData w samples intFmt
          wave     = if w == 1 then Binary name wd else WaveN name w wd
          cap      = do v <- readIORef (portRef port)
                        modifyIORef' samples (++ [v])
      modifyIORef' acc ((wave, cap):)
    ) rec
  reverse <$> readIORef acc

create :: (Interface i, Interface o) => Sim i o -> IO (Waveform, Sim i o)
create sim = do
  inW  <- collect (inputs sim)
  outW <- collect (outputs sim)
  let all_ = inW ++ outW
      captureAll = mapM_ snd all_
      waves = Clock "clock" : map fst all_
      step = simStep sim >> captureAll
  pure (Waveform waves, sim { simStep = step })
