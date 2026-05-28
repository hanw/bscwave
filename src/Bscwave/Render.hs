module Bscwave.Render where
import Data.IORef
import Bscwave.Waveform

sigInside :: Int
sigInside = 15

padR :: Int -> String -> String
padR n s = take n (s ++ repeat ' ')

groupRuns :: Eq a => [a] -> [(a, Int)]
groupRuns [] = []
groupRuns (x:xs) = let (same, rest) = span (== x) xs
                   in (x, 1 + length same) : groupRuns rest

renderWave :: Int -> Wave -> IO [(String, String)]
renderWave n (Clock nm) =
  pure
    [ (nm, take (n*8) (cycle "┌───┐   "))
    , ("", if n == 0 then "" else replicate 4 ' ' ++ take (n*8 - 4) (cycle "└───┘   "))
    ]
renderWave _ (Binary nm d) = do
  s <- readIORef (wdSamples d)
  let runs = groupRuns s
      pairs = zip (Nothing : map (Just . fst) runs) runs
      pickChars prev v = case (prev, v) of
        (Nothing, 0)  -> (' ', '─', ' ', '─')
        (Nothing, _)  -> ('─', ' ', '─', ' ')
        (Just 0, 1)   -> ('┌', '┘', '─', ' ')
        (Just 1, 0)   -> ('┐', '└', ' ', '─')
        (_, 0)        -> (' ', '─', ' ', '─')
        _             -> ('─', ' ', '─', ' ')
      renderRun (prev, (v, len)) =
        let w = len * 8
            (ft, fb, bt, bb) = pickChars prev v
        in (ft : replicate (w - 1) bt, fb : replicate (w - 1) bb)
      (tops, bots) = unzip (map renderRun pairs)
  pure
    [ (nm, concat tops)
    , ("", concat bots)
    ]
renderWave _ (WaveN nm _ d) = do
  s <- readIORef (wdSamples d)
  let fmt   = wdFormat d
      runs  = groupRuns s
      pairs = zip (Nothing : map (Just . fst) runs) runs
      renderRun (prev, (v, len)) =
        let wid = len * 8
            isTrans = case prev of { Nothing -> False; Just p -> p /= v }
        in ( (if isTrans then '┬' else '─') : replicate (wid - 1) '─'
           , (if isTrans then '│' else ' ') : padR (wid - 1) (fmt v)
           , (if isTrans then '┴' else '─') : replicate (wid - 1) '─'
           )
      (tops, mids, bots) = unzip3 (map renderRun pairs)
  pure
    [ ("", concat tops)
    , (nm, concat mids)
    , ("", concat bots)
    ]

print :: Waveform -> IO ()
print (Waveform ws) = do
  n <- case [d | w <- ws, Just d <- [waveData w]] of
         (d:_) -> length <$> readIORef (wdSamples d)
         []    -> pure 0
  rows <- concat <$> mapM (renderWave n) ws
  let ww = max 1 (n * 8)
      fillBorder len lbl = lbl ++ replicate (len - length lbl) '─'
  putStrLn $ "┌" ++ fillBorder sigInside "Signals" ++ "┐┌" ++ fillBorder ww "Waves" ++ "┐"
  mapM_ (\(lbl, content) ->
    putStrLn $ "│" ++ padR sigInside lbl ++ "││" ++ padR ww content ++ "│") rows
  putStrLn $ "│" ++ replicate sigInside ' ' ++ "││" ++ replicate ww ' ' ++ "│"
  putStrLn $ "└" ++ replicate sigInside '─' ++ "┘└" ++ replicate ww '─' ++ "┘"
