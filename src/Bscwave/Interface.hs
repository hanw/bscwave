{-# LANGUAGE DataKinds #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE AllowAmbiguousTypes #-}
module Bscwave.Interface
  ( Bit, bit, unBit, bitWidth
  , Port (..), portWidth, readPort, writePort
  , Interface (..)
  -- * Display formatters
  , formatPort, defaultFormat
  , hexFormat, decimalFormat, signedDecimalFormat, binaryFormat
  , lanesFormat
  ) where

import Data.IORef
import Data.Bits ((.&.), shiftL, shiftR)
import Data.List (intercalate)
import Data.Proxy (Proxy (..))
import GHC.TypeLits (Nat, KnownNat, natVal)
import Numeric (showHex, showIntAtBase)
import Data.Char (intToDigit)

-- | A bit vector of statically known width. Values are masked to width on
-- construction, so out-of-range integer literals wrap rather than corrupt
-- adjacent ports.
newtype Bit (n :: Nat) = Bit { unBit :: Integer }
  deriving (Eq, Ord, Show)

bit :: forall n. KnownNat n => Integer -> Bit n
bit v = Bit (v .&. mask)
  where w = fromInteger (natVal (Proxy @n)) :: Int
        mask = (1 `shiftL` w) - 1

bitWidth :: forall n. KnownNat n => Bit n -> Int
bitWidth _ = fromInteger (natVal (Proxy @n))

instance KnownNat n => Num (Bit n) where
  fromInteger        = bit @n
  Bit a + Bit b      = bit @n (a + b)
  Bit a - Bit b      = bit @n (a - b)
  Bit a * Bit b      = bit @n (a * b)
  abs                = id
  signum (Bit 0)     = Bit 0
  signum _           = Bit 1
  negate (Bit a)     = bit @n (negate a)

-- | A simulator port with statically known width. 'portBscName' is the bsc
-- symbol-table path (e.g. "EN_clear"); 'portRef' holds the staged input or
-- last sampled output value; 'portFormat' is the display formatter used by
-- the waveform renderer (defaults to 'hexFormat').
data Port (n :: Nat) = Port
  { portBscName :: String
  , portRef     :: IORef Integer
  , portFormat  :: IORef (Bit n -> String)
  }

portWidth :: forall n. KnownNat n => Port n -> Int
portWidth _ = fromInteger (natVal (Proxy @n))

readPort :: forall n. KnownNat n => Port n -> IO (Bit n)
readPort p = bit @n <$> readIORef (portRef p)

writePort :: forall n. KnownNat n => Port n -> Bit n -> IO ()
writePort p v = writeIORef (portRef p) (unBit v)

-- | Attach a custom display formatter to a port. The formatter is used by
-- 'Bscwave.Render.print' to convert the sampled bit pattern into the text
-- shown in each cycle's column. Must be called before 'Bscwave.Waveform.create'
-- — the waveform snapshots the formatter at capture time so post-hoc changes
-- have no effect on already-collected samples.
formatPort :: forall n. Port n -> (Bit n -> String) -> IO ()
formatPort p f = writeIORef (portFormat p) f

-- | The default formatter, matching the pre-formatter renderer: zero-padded
-- hex with one nibble per 4 bits (rounded up).
defaultFormat :: forall n. KnownNat n => Bit n -> String
defaultFormat = hexFormat

-- | Zero-padded hex. Width comes from the type-level 'Nat' of the 'Bit'.
hexFormat :: forall n. KnownNat n => Bit n -> String
hexFormat (Bit v) = replicate (nibbles - length h) '0' ++ h
  where
    w       = fromInteger (natVal (Proxy @n)) :: Int
    nibbles = (w + 3) `div` 4
    h       = showHex v ""

-- | Unsigned decimal.
decimalFormat :: forall n. Bit n -> String
decimalFormat (Bit v) = show v

-- | Signed decimal: bits are interpreted as two's-complement of the type
-- width, so 0xFFFFFFFF in a @Bit 32@ renders as @-1@.
signedDecimalFormat :: forall n. KnownNat n => Bit n -> String
signedDecimalFormat (Bit v)
  | v >= half = show (v - whole)
  | otherwise = show v
  where
    w     = fromInteger (natVal (Proxy @n)) :: Int
    whole = 1 `shiftL` w
    half  = 1 `shiftL` (w - 1)

-- | Bit-level binary, zero-padded to width.
binaryFormat :: forall n. KnownNat n => Bit n -> String
binaryFormat (Bit v) = replicate (w - length b) '0' ++ b
  where
    w = fromInteger (natVal (Proxy @n)) :: Int
    b = showIntAtBase 2 intToDigit v ""

-- | Render a value packed as @numLanes@ lanes of @laneBits@ bits each as
-- @"[v0, v1, ...]"@. Element 0 is taken from the high bits (matches bsc's
-- @pack@ convention for @Vector#(n, T)@). @showLane@ formats each lane
-- (e.g. @show@ for raw, or @show . signed laneBits@ for two's-complement).
--
-- > formatPort (V.execute_src1 i)
-- >            (lanesFormat 4 32 (signedDecimalFormat @32 . bit @32))
lanesFormat
  :: forall n. Int           -- ^ number of lanes
              -> Int         -- ^ bits per lane
              -> (Integer -> String)  -- ^ per-lane renderer (raw bits)
              -> Bit n -> String
lanesFormat numLanes laneBits showLane (Bit v) =
  "[" ++ intercalate "," (map renderLane [0 .. numLanes - 1]) ++ "]"
  where
    mask       = (1 `shiftL` laneBits) - 1
    renderLane i =
      showLane ((v `shiftR` ((numLanes - 1 - i) * laneBits)) .&. mask)

-- | A higher-kinded record describing a model's input or output ports.
--
-- A typical generated declaration looks like:
--
-- @
-- data Inputs f = Inputs { en_clear :: f 1, en_incr :: f 1 }
-- instance Interface Inputs where
--   mkInterface k = Inputs \<$\> k \@1 "EN_clear" \<*\> k \@1 "EN_incr"
--   traverseI_ f (Inputs a b) = f "EN_clear" a *> f "EN_incr" b
-- @
class Interface (a :: (Nat -> *) -> *) where
  -- | Build the record by invoking the callback once per field. The callback
  -- receives the bsc symbol name; the field width comes from the type.
  mkInterface
    :: Applicative m
    => (forall n. KnownNat n => String -> m (f n))
    -> m (a f)

  -- | Visit each field in declaration order.
  traverseI_
    :: Applicative m
    => (forall n. KnownNat n => String -> f n -> m ())
    -> a f -> m ()
