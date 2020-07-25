module Marlowe.ActusBlockly where

import Data.Time.Calendar.Days
import Language.Marlowe.ACTUS.Definitions.ContractTerms
import Prelude

import Affjax.RequestBody (RequestBody(..))
import Blockly (AlignDirection(..), Arg(..), BlockDefinition(..), block, blockType, category, colour, defaultBlockDefinition, getBlockById, initializeWorkspace, name, render, style, x, xml, y)
import Blockly.Generator (Connection, Generator, Input, NewBlockFunction, clearWorkspace, connect, connectToOutput, connectToPrevious, fieldName, fieldRow, getBlockInputConnectedTo, getFieldValue, getInputWithName, getType, inputList, inputName, inputType, insertGeneratorFunction, mkGenerator, nextBlock, nextConnection, previousConnection, setFieldText, statementToCode)
import Blockly.Types (Block, BlocklyState, Workspace)
import Control.Alternative ((<|>))
import Control.Category (identity)
import Control.Monad.Except (mapExcept, runExcept)
import Control.Monad.ST as ST
import Control.Monad.ST.Internal (ST, STRef)
import Control.Monad.ST.Ref as STRef
import Data.Array (filter, head, uncons, (:))
import Data.Array as Array
import Data.Bifunctor (lmap, rmap)
import Data.Either (Either, note)
import Data.Either as Either
import Data.Enum (class BoundedEnum, class Enum, upFromIncluding)
import Data.Function (const)
import Data.Generic.Rep (class Generic)
import Data.Generic.Rep.Bounded (genericBottom, genericTop)
import Data.Generic.Rep.Enum (genericCardinality, genericFromEnum, genericPred, genericSucc, genericToEnum)
import Data.Generic.Rep.Eq (genericEq)
import Data.Generic.Rep.Ord (genericCompare)
import Data.Generic.Rep.Show (genericShow)
import Data.Lens (to, view, (^.))
import Data.Maybe (Maybe(..))
import Data.Newtype (class Newtype, unwrap)
import Data.Traversable (traverse, traverse_)
import Data.Tuple (Tuple(..))
import Foreign (F, readString, Foreign)
import Foreign.Class (class Encode, class Decode, encode, decode)
import Foreign.Generic (genericEncode, genericDecode, encodeJSON)
import Foreign.Generic.Class (Options, defaultOptions, aesonSumEncoding)
import Foreign.JSON (parseJSON)
import Foreign.NullOrUndefined (undefined)
import Halogen.HTML (HTML)
import Halogen.HTML.Properties (id_)
import Language.Marlowe.ACTUS.Definitions.ContractTerms (ContractTerms(..), Cycle(..), EOMC, ScheduleConfig(..))
import Marlowe.Holes (AccountId(..), Action(..), Bound(..), Case(..), ChoiceId(..), Contract(..), Observation(..), Party(..), Payee(..), Term(..), TermWrapper(..), Token(..), Value(..), ValueId(..), mkDefaultTerm, mkDefaultTermWrapper)
import Marlowe.Parser as Parser
import Marlowe.Semantics (Rational(..))
import Record (merge)
import Text.Parsing.StringParser (Parser)
import Text.Parsing.StringParser.Basic (parens, runParser')
import Type.Proxy (Proxy(..))

rootBlockName :: String
rootBlockName = "root_contract"


data ActusContractType
  = PaymentAtMaturity

derive instance actusContractType :: Generic ActusContractType _

instance showActusContractType :: Show ActusContractType where
  show = genericShow

instance eqActusContractType :: Eq ActusContractType where
  eq = genericEq

instance ordActusContractType :: Ord ActusContractType where
  compare = genericCompare

instance enumActusContractType :: Enum ActusContractType where
  succ = genericSucc
  pred = genericPred

instance boundedActusContractType :: Bounded ActusContractType where
  bottom = genericBottom
  top = genericTop

instance boundedEnumActusContractType :: BoundedEnum ActusContractType where
  cardinality = genericCardinality
  toEnum = genericToEnum
  fromEnum = genericFromEnum

actusContractTypes :: Array ActusContractType
actusContractTypes = upFromIncluding bottom


data ActusValueType =
  ActusDate
  | ActusCycle
  | Decimal
  | PenaltyType
  | ContractRole
  | FeeBasis
  | ActusScheduleConfig


derive instance actusActusValueType :: Generic ActusValueType _

instance showActusValueType :: Show ActusValueType where
  show = genericShow

instance eqActusValueType :: Eq ActusValueType where
  eq = genericEq

instance ordActusValueType :: Ord ActusValueType where
  compare = genericCompare

instance enumActusValueType :: Enum ActusValueType where
  succ = genericSucc
  pred = genericPred

instance boundedActusValueType :: Bounded ActusValueType where
  bottom = genericBottom
  top = genericTop

instance boundedEnumActusValueType :: BoundedEnum ActusValueType where
  cardinality = genericCardinality
  toEnum = genericToEnum
  fromEnum = genericFromEnum

actusValueTypes :: Array ActusValueType
actusValueTypes = upFromIncluding bottom


data BlockType
  = BaseContractType
  | ActusContractType ActusContractType
  | ActusValueType ActusValueType

derive instance genericBlockType :: Generic BlockType _

instance eqBlockType :: Eq BlockType where
  eq = genericEq

instance ordBlockType :: Ord BlockType where
  compare = genericCompare

instance enumBlockType :: Enum BlockType where
  succ = genericSucc
  pred = genericPred

instance boundedBlockType :: Bounded BlockType where
  bottom = genericBottom
  top = genericTop

instance boundedEnumBlockType :: BoundedEnum BlockType where
  cardinality = genericCardinality
  toEnum = genericToEnum
  fromEnum = genericFromEnum

instance showBlockType :: Show BlockType where
  show BaseContractType = "BaseContractType"
  show (ActusContractType c) = show c
  show (ActusValueType c) = show c

contractColour :: String
contractColour = "#a380bc"

boundsColour :: String
boundsColour = "#1a7b84"

actionColour :: String
actionColour = "#e6aa00"

observationColour :: String
observationColour = "#1fc1c3"

valueColour :: String
valueColour = "#eb2256"

payeeColour :: String
payeeColour = "#709cf0"

partyColour :: String
partyColour = "#f69ab2"

tokenColour :: String
tokenColour = "#eb4a22"

blockColour :: BlockType -> String
blockColour BaseContractType = contractColour

blockColour (ActusContractType _) = boundsColour

blockColour (ActusValueType _) = actionColour

blockDefinitions :: Array BlockDefinition
blockDefinitions = map toDefinition (upFromIncluding bottom)

toDefinition :: BlockType -> BlockDefinition
toDefinition BaseContractType =
  BlockDefinition
    $ merge
        { type: show BaseContractType
        , message0: "%1 CONTRACT %2 %3 %4 %5"
        , args0:
          [ DummyRight
          , DummyRight
          , DummyRight
          , Statement { name: (show BaseContractType), check: (show BaseContractType), align: Right }
          , DummyRight
          ]
        , colour: blockColour BaseContractType
        , inputsInline: Just false
        }
        defaultBlockDefinition
toDefinition (ActusContractType PaymentAtMaturity) = 
  BlockDefinition
    $ merge
        { type: show PaymentAtMaturity
        , message0: "Payment At Maturity %1 initial exchange date * %2 %3 %4 %5 %6"
        , args0:
          [ DummyCentre
          , Value { name: "initial_exchange_date", check: "date", align: Right }
          , DummyRight
          , DummyRight
          , DummyRight
          , DummyRight
          ]
        , colour: blockColour BaseContractType
        , previousStatement: Just (show BaseContractType)
        , inputsInline: Just false
        }
        defaultBlockDefinition

toDefinition (ActusValueType ActusDate) = 
  BlockDefinition
    $ merge
        { type: show ActusDate
        , message0: "ActusDate %1"
        , args0:
          [ Input { name: "date", text: "2020-10-10", spellcheck: false }
          ]
        , colour: blockColour BaseContractType
        , output: Just "date"
        , inputsInline: Just false
        }
        defaultBlockDefinition

toDefinition (ActusValueType ActusCycle) = 
  BlockDefinition
    $ merge
        { type: show ActusCycle
        , message0: "%1 ActusCycle %2 %3 %4 %5"
        , args0:
          [ DummyRight
          , DummyRight
          , DummyRight
          , DummyRight
          , DummyRight
          ]
        , colour: blockColour BaseContractType
        , inputsInline: Just false
        }
        defaultBlockDefinition

toDefinition (ActusValueType Decimal) = 
  BlockDefinition
    $ merge
        { type: show Decimal
        , message0: "%1 Decimal %2 %3 %4 %5"
        , args0:
          [ DummyRight
          , DummyRight
          , DummyRight
          , DummyRight
          , DummyRight
          ]
        , colour: blockColour BaseContractType
        , inputsInline: Just false
        }
        defaultBlockDefinition

toDefinition (ActusValueType PenaltyType) = 
  BlockDefinition
    $ merge
        { type: show PenaltyType
        , message0: "%1 Decimal %2 %3 %4 %5"
        , args0:
          [ DummyRight
          , DummyRight
          , DummyRight
          , DummyRight
          , DummyRight
          ]
        , colour: blockColour BaseContractType
        , inputsInline: Just false
        }
        defaultBlockDefinition

toDefinition (ActusValueType ContractRole) = 
  BlockDefinition
    $ merge
        { type: show ContractRole
        , message0: "%1 ContractRole %2 %3 %4 %5"
        , args0:
          [ DummyRight
          , DummyRight
          , DummyRight
          , DummyRight
          , DummyRight
          ]
        , colour: blockColour BaseContractType
        , inputsInline: Just false
        }
        defaultBlockDefinition

toDefinition (ActusValueType FeeBasis) = 
  BlockDefinition
    $ merge
        { type: show FeeBasis
        , message0: "%1 FeeBasis %2 %3 %4 %5"
        , args0:
          [ DummyRight
          , DummyRight
          , DummyRight
          , DummyRight
          , DummyRight
          ]
        , colour: blockColour BaseContractType
        , inputsInline: Just false
        }
        defaultBlockDefinition

toDefinition (ActusValueType ActusScheduleConfig) = 
  BlockDefinition
    $ merge
        { type: show ActusScheduleConfig
        , message0: "%1 ScheduleConfig %2 %3 %4 %5"
        , args0:
          [ DummyRight
          , DummyRight
          , DummyRight
          , DummyRight
          , DummyRight
          ]
        , colour: blockColour BaseContractType
        , inputsInline: Just false
        }
        defaultBlockDefinition


toolbox :: forall a b. HTML a b
toolbox =
  xml [ id_ "actusBlocklyToolbox", style "display:none" ]
    [ category [ name "Contract Types", colour contractColour ] (map mkBlock actusContractTypes)
    , category [ name "Value", colour observationColour ] (map mkBlock actusValueTypes)
    , category [ name "Cycles", colour actionColour ] (map mkBlock actusValueTypes)
    , category [ name "Assertions", colour valueColour ] (map mkBlock actusValueTypes)
    ]
  where
  mkBlock :: forall t. Show t => t -> _
  mkBlock t = block [ blockType (show t) ] []

workspaceBlocks :: forall a b. HTML a b
workspaceBlocks =
  xml [ id_ "actusBlocklyWorkspace", style "display:none" ]
    [ block [ blockType (show BaseContractType), x "13", y "187", id_ rootBlockName ] []
    ]

parse :: forall a. Parser a -> String -> Either String a
parse p = lmap show <<< runParser' (parens p <|> p)

buildGenerator :: BlocklyState -> Generator
buildGenerator blocklyState =
  ST.run
    ( do
        gRef <- mkGenerator blocklyState "Actus"
        g <- STRef.read gRef
        traverse_ (\t -> mkGenFun gRef t (baseContractDefinition g)) [ BaseContractType ]
        traverse_ (\t -> mkGenFun gRef t (blockDefinition t g)) actusContractTypes
        traverse_ (\t -> mkGenFun gRef t (blockDefinition t g)) actusValueTypes
        STRef.read gRef
    )

mkGenFun :: forall a r t. Show a => Show t => STRef r Generator -> t -> (Block -> Either String a) -> ST r Unit
mkGenFun generator blockType f = insertGeneratorFunction generator (show blockType) ((rmap show) <<< f)

class HasBlockDefinition a b | a -> b where
  blockDefinition :: a -> Generator -> Block -> Either String b

baseContractDefinition :: Generator -> Block -> Either String ActusContract
baseContractDefinition g block = 
  do 
    code <- statementToCode g block (show BaseContractType)
    json <- catch $ runExcept $ parseJSON code
    catch $ runExcept (decode json :: F ActusContract)

newtype ActusContract = ActusContract {
  startDate :: ActusValue
  , initialExchangeDate :: ActusValue
  , maturityDate :: ActusValue
  , terminationDate :: ActusValue
  , purchaseDate :: ActusValue
  , dayCountConvention :: ActusValue
  , endOfMonthConvention :: ActusValue
}

derive instance actusContract :: Generic ActusContract _

derive instance actusContractNewtype :: Newtype ActusContract _

instance showActusContract :: Show ActusContract where
  show = encodeJSON

instance encodeJsonActusContract :: Encode ActusContract where
  encode a = genericEncode aesonCompatibleOptions a

instance decodeJsonActusContract :: Decode ActusContract where
  decode a = genericDecode aesonCompatibleOptions a

data ActusValue = DateValue Int | NoActusValue | ActusError String

derive instance actusValue :: Generic ActusValue _

instance showActusValue :: Show ActusValue where
  show = encodeJSON

instance encodeJsonActusValue :: Encode ActusValue where
  encode a = genericEncode aesonCompatibleOptions a

instance decodeJsonActusValue :: Decode ActusValue where
  decode a = genericDecode aesonCompatibleOptions a

catch :: forall a b. Show a => Either a b -> Either String b
catch = lmap show

parseFieldActusValueJson :: Generator -> Block -> String -> ActusValue
parseFieldActusValueJson g block name = 
  Either.either (const NoActusValue) identity result 
    where 
      result = do
        value <- statementToCode g block name
        parsed <- catch $ runExcept $ parseJSON value
        let decoded = decode parsed :: F ActusValue
        catch $ runExcept $ decoded

parseActusJsonCode :: String -> Either String ContractTerms
parseActusJsonCode str = do
  parsed <- catch $ runExcept $ parseJSON str
  let decoded = decode parsed :: F ActusContract
  result <- catch $ runExcept $ decoded 
  pure $ actusContractToTerms result

instance hasBlockDefinitionActusContract :: HasBlockDefinition ActusContractType ActusContract where
  blockDefinition _ g block = Either.Right $ ActusContract {
    startDate : parseFieldActusValueJson g block "start_date"
    , initialExchangeDate : parseFieldActusValueJson g block "initial_exchange_date"
    , maturityDate : parseFieldActusValueJson g block "maturity_date"
    , terminationDate : parseFieldActusValueJson g block "termination_date"
    , purchaseDate : parseFieldActusValueJson g block "purchase_date"
    , dayCountConvention : parseFieldActusValueJson g block "day_count_convention"
    , endOfMonthConvention : parseFieldActusValueJson g block "end_of_month_convention"
  }
  
instance hasBlockDefinitionValue :: HasBlockDefinition ActusValueType ActusValue where
  blockDefinition ActusDate g block = do 
    -- date <- getFieldValue block "date"
    pure $ DateValue 100
  blockDefinition _ g block = Either.Right NoActusValue

actusDateToDay :: ActusValue -> String
actusDateToDay date = "2020-10-10"

actusContractToTerms :: ActusContract -> ContractTerms
actusContractToTerms c =
  ContractTerms
      { contractId : "0"
      , contractType : PAM
      , ct_IED : actusDateToDay (unwrap c).initialExchangeDate
      , ct_SD : actusDateToDay (unwrap c).initialExchangeDate
      , ct_MD : actusDateToDay (unwrap c).maturityDate
      , ct_TD : actusDateToDay (unwrap c).terminationDate
      , ct_PRD : actusDateToDay (unwrap c).purchaseDate
      , ct_CNTRL : CR_ST
      , ct_PDIED : -100.0
      , ct_NT : 1000.0
      , ct_PPRD : 1200.0
      , ct_PTD : 1200.0
      , ct_DCC : DCC_A_360
      , ct_PREF : PREF_N
      , ct_PRF : CS_PF
      , scfg : ScheduleConfig {
            calendar : []
            , includeEndDay : false
            , eomc : EOMC_EOM
            , bdc : BDC_NULL
        }
      , ct_PYRT : 0.0
      , ct_PYTP : PYTP_A
      , ct_cPYRT : 0.0
      , ct_OPCL : Nothing
      , ct_OPANX : Nothing
      , ct_SCIED : 0.0
      , ct_SCEF : SE_000
      , ct_SCCL : Nothing
      , ct_SCANX : Nothing
      , ct_SCIXSD : 0.0
      , ct_RRCL : Nothing
      , ct_RRANX : Nothing
      , ct_RRNXT : Nothing
      , ct_RRSP : 0.0
      , ct_RRMLT : 0.0
      , ct_RRPF : 0.0
      , ct_RRPC : 0.0
      , ct_RRLC : 0.0
      , ct_RRLF : 0.0
      , ct_IPCED : Nothing
      , ct_IPCL : Nothing
      , ct_IPANX : Nothing
      , ct_IPNR : Nothing
      , ct_IPAC : Nothing
      , ct_FECL : Nothing
      , ct_FEANX : Nothing
      , ct_FEAC : Nothing
      , ct_FEB : FEB_N
      , ct_FER : 0.0
      }



aesonCompatibleOptions :: Options
aesonCompatibleOptions =
  defaultOptions
    { unwrapSingleConstructors = true
    , sumEncoding = aesonSumEncoding
    }