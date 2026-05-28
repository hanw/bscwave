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
  ) where

import Data.IORef
import Data.Bits ((.&.), shiftL)
import Data.Proxy (Proxy (..))
import GHC.TypeLits (Nat, KnownNat, natVal)

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
-- symbol-table path (e.g. "EN_clear"); the IORef holds the staged input or
-- last sampled output value.
data Port (n :: Nat) = Port { portBscName :: String, portRef :: IORef Integer }

portWidth :: forall n. KnownNat n => Port n -> Int
portWidth _ = fromInteger (natVal (Proxy @n))

readPort :: forall n. KnownNat n => Port n -> IO (Bit n)
readPort p = bit @n <$> readIORef (portRef p)

writePort :: forall n. KnownNat n => Port n -> Bit n -> IO ()
writePort p v = writeIORef (portRef p) (unBit v)

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
