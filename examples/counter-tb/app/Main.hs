{-# LANGUAGE TypeApplications #-}
module Main where

import Bscwave.Interface
import Bscwave.Sim
import qualified Bscwave.Waveform as Waveform
import qualified Bscwave.Render as Render
import qualified MkCounter as C

testbench :: IO Waveform.Waveform
testbench = do
  sim <- create @C.Inputs @C.Outputs C.modelName
  (waves, sim') <- Waveform.create sim
  let i = inputs sim'
      step cl ic = do
        writePort (C.en_clear i) cl
        writePort (C.en_incr  i) ic
        simStep sim'
  mapM_ (uncurry step) [(0,0),(0,1),(0,1),(1,0),(0,0),(0,0)]
  pure waves

main :: IO ()
main = testbench >>= Render.print
