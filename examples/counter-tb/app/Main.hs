module Main where

import Bscwave.Sim
import Bscwave.Waveform (Waveform)
import qualified Bscwave.Waveform as Waveform
import qualified Bscwave.Render as Render
import Data.IORef

testbench :: IO Waveform
testbench = do
  sim <- create "mkCounter" [("EN_clear",1),("EN_incr",1)] [("count",8)]
  (waves, sim') <- Waveform.create sim
  let step cl inc = writeIORef (input sim' "EN_clear") cl
                 >> writeIORef (input sim' "EN_incr") inc
                 >> simStep sim'
  mapM_ (uncurry step) [(0,0),(0,1),(0,1),(1,0),(0,0),(0,0)]
  return waves

main :: IO ()
main = testbench >>= Render.print

