{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE GADTs                 #-}
{-# LANGUAGE KindSignatures        #-}
{-# LANGUAGE ScopedTypeVariables   #-}
{-# LANGUAGE TypeOperators         #-}
{-# LANGUAGE TypeFamilies          #-}
{-# LANGUAGE PolyKinds             #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE LambdaCase            #-}

module Grenade.Core.Network (
    Layer (..)
  , Network (..)
  , UpdateLayer (..)
  , LearningParameters (..)
  , Gradients (..)
  , CreatableNetwork (..)
  ) where

import           Control.Monad.Random (MonadRandom)

import           Data.Serialize

import           Grenade.Core.Shape

data LearningParameters = LearningParameters {
    learningRate :: Double
  , learningMomentum :: Double
  , learningRegulariser :: Double
  } deriving (Eq, Show)

-- | Class for updating a layer. All layers implement this, and it is
--   shape independent.
class Show x => UpdateLayer x where
  -- | The type for the gradient for this layer.
  --   Unit if there isn't a gradient to pass back.
  type Gradient x :: *
  -- | Update a layer with its gradient and learning parameters
  runUpdate       :: LearningParameters -> x -> Gradient x -> x
  -- | Create a random layer, many layers will use pure
  createRandom    :: MonadRandom m => m x

-- | Class for a layer. All layers implement this, however, they don't
--   need to implement it for all shapes, only ones which are appropriate.
class UpdateLayer x => Layer x (i :: Shape) (o :: Shape) where
  -- | Used in training and scoring. Take the input from the previous
  --   layer, and give the output from this layer.
  runForwards    :: x -> S' i -> S' o
  -- | Back propagate a step. Takes the current layer, the input that the
  --   layer gave from the input and the back propagated derivatives from
  --   the layer above.
  --   Returns the gradient layer and the derivatives to push back further.
  runBackwards   :: x -> S' i -> S' o -> (Gradient x, S' i)

-- | Type of a network.
--   The [*] type specifies the types of the layers. This is needed for parallel
--   running and being all the gradients beck together.
--   The [Shape] type specifies the shapes of data passed between the layers.
--   Could be considered to be a heterogeneous list of layers which are able to
--   transform the data shapes of the network.
data Network :: [*] -> [Shape] -> * where
    O     :: Layer x i o => !x -> Network '[x] '[i, o]
    (:~>) :: Layer x i h => !x -> !(Network xs (h ': hs)) -> Network (x ': xs) (i ': h ': hs)
infixr 5 :~>

instance Show (Network l h) where
  show (O a) = "O " ++ show a
  show (i :~> o) = show i ++ "\n:~>\n" ++ show o

-- | Gradients of a network.
--   Parameterised on the layers of a Network.
data Gradients :: [*] -> * where
   OG    :: UpdateLayer x => Gradient x -> Gradients '[x]
   (:/>) :: UpdateLayer x => Gradient x -> Gradients xs -> Gradients (x ': xs)


-- | A network can easily be created by hand with (:~>), but an easy way to initialise a random
--   network is with the randomNetwork.
class CreatableNetwork (xs :: [*]) (ss :: [Shape]) where
  -- | Create a network of the types requested
  randomNetwork :: MonadRandom m => m (Network xs ss)

instance Layer x i o => CreatableNetwork (x ': '[]) (i ': o ': '[]) where
  randomNetwork = O <$> createRandom

instance (Layer x i o, CreatableNetwork xs (o ': r ': rs)) => CreatableNetwork (x ': xs) (i ': o ': r ': rs) where
  randomNetwork = (:~>) <$> createRandom <*> randomNetwork


-- | Add very simple serialisation to the network
instance (Layer x i o, Serialize x) => Serialize (Network '[x] '[i, o]) where
  put (O x) = put x
  put _ = error "impossible"
  get = O <$> get

instance (Layer x i o, Serialize x, Serialize (Network xs (o ': r ': rs))) => Serialize (Network (x ': xs) (i ': o ': r ': rs)) where
  put (x :~> r) = put x >> put r
  get = (:~>) <$> get <*> get
