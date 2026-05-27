module Bscwave.FFI where
import Foreign
import Foreign.C

foreign import ccall "bsim_create"        bsim_create        :: CInt -> Ptr CString -> IO (Ptr ())
foreign import ccall "bsim_destroy"       bsim_destroy       :: Ptr () -> IO ()
foreign import ccall "bsim_clock_posedge" bsim_clock_posedge :: Ptr () -> CString -> IO ()
foreign import ccall "bsim_clock_negedge" bsim_clock_negedge :: Ptr () -> CString -> IO ()
foreign import ccall "bsim_set_param"     bsim_set_param     :: Ptr () -> CString -> Ptr Word32 -> CInt -> IO CInt
foreign import ccall "bsim_get_result"    bsim_get_result    :: Ptr () -> CString -> Ptr Word32 -> CInt -> IO CInt

