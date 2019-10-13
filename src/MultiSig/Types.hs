{-# LANGUAGE NoApplicativeDo, RebindableSyntax #-}
{-# OPTIONS_GHC -Wno-unused-do-bind #-}

-- | Types defined in this module are not used directly.
-- Only DecodeSlice/EncodeBuilder instances are valuable.
-- These types are only defined for clarity.

module MultiSig.Types
       ( SignMsg (..)
       , SignMsgBody (..)
       , Storage (..)
       , Order (..)
       , Nonce (..)
       , OrderDict
       , SignDict
       , MultiSigError (..)
       , decodeMsgFromSliceFull
       ) where

import Prelude

import FiftAsm

newtype Nonce = Nonce Word32

type instance ToTVM Nonce = 'IntT

instance DecodeSlice Nonce where
    decodeFromSlice = ld32Unsigned

instance EncodeBuilder Nonce where
    encodeToBuilder = st32Unsigned

-- data Msg = GetAllOrders | GetOrdersByKey PublicKey | SignMsg_ SignMsg

decodeMsgFromSliceFull
  :: '[] :-> '[]
  -> '[Bool, PublicKey] :-> '[]
  -> DecodeSliceFields SignMsg :-> '[]
  -> '[Slice] :-> '[]
decodeMsgFromSliceFull handleGetAll handleGetByKey handleSignMsg = do
  decodeFromSlice @Word32
  swap
  dup
  pushInt 3
  if IsGt
    then throw ErrorParsingMsg
    else ignore
  stacktype @'[Word32, Slice]
  dup
  pushInt 2
  if IsGt
    then do
      drop
      endS
      handleGetAll
    else do
      dup
      pushInt 0
      if IsGt
        then do
          pushInt 1
          equalInt
          swap
          decodeFromSlice @PublicKey
          endS
          swap
          handleGetByKey
        else do
          drop
          decodeFromSlice @SignMsg
          endS
          handleSignMsg

-- Msg part
type SignDict = Dict PublicKey Signature
data SignMsg = SignMsg
    { msgNonce      :: Nonce
    , msgSignatures :: SignDict
    , msgBody       :: Cell SignMsgBody
    }

data SignMsgBody = SignMsgBody
    { mbExpiration :: Timestamp
    , mbMsgObj     :: Cell MessageObject
    }

instance DecodeSlice SignMsg where
    type DecodeSliceFields SignMsg = [Cell SignMsgBody, SignDict, Nonce]
    decodeFromSlice = do
        decodeFromSlice @Nonce
        decodeFromSlice @SignDict
        decodeFromSlice @(Cell SignMsgBody)

instance DecodeSlice SignMsgBody where
    type DecodeSliceFields SignMsgBody = [Cell MessageObject, Timestamp]
    decodeFromSlice = do
        decodeFromSlice @Timestamp
        decodeFromSlice @(Cell MessageObject)

-- Storage part
type OrderDict =  Dict (Hash SignMsgBody) Order
data Storage = Storage
    { sOrders :: OrderDict
    , sNonce  :: Nonce
    , sK      :: Word32
    , sPKs    :: DSet PublicKey
    }

data Order = Order
    { oMsgBody    :: Cell SignMsgBody
    , oApproved   :: DSet PublicKey
    }

instance DecodeSlice Storage where
    type DecodeSliceFields Storage = [OrderDict, DSet PublicKey, Word32, Nonce]
    decodeFromSlice = do
        decodeFromSlice @Nonce
        decodeFromSlice @Word32
        decodeFromSlice @(DSet PublicKey)
        decodeFromSlice @OrderDict

instance EncodeBuilder Storage where
    encodeToBuilder = do
        encodeToBuilder @Nonce
        encodeToBuilder @Word32
        encodeToBuilder @(DSet PublicKey)
        encodeToBuilder @OrderDict

instance DecodeSlice Order where
    type DecodeSliceFields Order = [DSet PublicKey, Cell SignMsgBody]
    decodeFromSlice = do
        decodeFromSlice @(Cell SignMsgBody)
        decodeFromSlice @(DSet PublicKey)

instance EncodeBuilder Order where
    encodeToBuilder = do
        encodeToBuilder @(Cell SignMsgBody)
        encodeToBuilder @(DSet PublicKey)

type instance ToTVM Order = 'SliceT

data MultiSigError
    = NonceMismatch
    | MsgExpired
    | NoValidSignatures
    | ErrorParsingMsg
    deriving (Eq, Ord, Show, Generic)

instance Exception MultiSigError

instance Enum MultiSigError where
    toEnum 32 = NonceMismatch
    toEnum 33 = MsgExpired
    toEnum 34 = NoValidSignatures
    toEnum 35 = ErrorParsingMsg
    toEnum _ = error "Uknown MultiSigError id"

    fromEnum NonceMismatch = 32
    fromEnum MsgExpired = 33
    fromEnum NoValidSignatures = 34
    fromEnum ErrorParsingMsg = 35
