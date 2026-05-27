module Bscwave.Waveform where
import Data.IORef
import qualified Data.Map.Strict as Map
import Bscwave.Sim

data WaveData = WaveData { wdWidth :: Int, wdSamples :: IORef [Integer] }
data Wave     = Clock String | Binary String WaveData | WaveN String Int WaveData
data Waveform = Waveform { wfWaves :: [Wave] }

newWave :: Port -> IO Wave
newWave p = do
  d <- WaveData (portWidth p) <$> newIORef []
  pure $ if portWidth p == 1 then Binary (portName p) d else WaveN (portName p) (portWidth p) d

waveData :: Wave -> Maybe WaveData
waveData (Binary _ d) = Just d
waveData (WaveN _ _ d) = Just d
waveData _ = Nothing

capture :: Wave -> Port -> IO ()
capture w p = case waveData w of
  Nothing -> pure ()
  Just d  -> do
    v <- readIORef (portRef p)
    modifyIORef' (wdSamples d) (++ [v])

waveName :: Wave -> String
waveName (Clock n) = n
waveName (Binary n _) = n
waveName (WaveN n _ _) = n

create :: Sim -> IO (Waveform, Sim)
create sim = do
  let ports = Map.elems (simInputs sim) ++ Map.elems (simOutputs sim)
  waves <- mapM newWave ports
  let captureAll = mapM_ (uncurry capture) (zip waves ports)
      allW = Clock "clock" : waves
      step = simStep sim >> captureAll
  pure (Waveform allW, sim { simStep = step })
