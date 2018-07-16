{-# Language ScopedTypeVariables, BangPatterns, DeriveDataTypeable #-}

module Main where

import Control.Exception.Safe
import Control.Concurrent.Async
import Control.Concurrent.MVar
import Control.Exception.Base (BlockedIndefinitelyOnMVar, BlockedIndefinitelyOnSTM)
import Data.Traversable
import Data.List as L
import Data.Maybe
import Data.Either
import qualified Data.Vector as V
import Data.Typeable
import Debug.Trace

data HighNumberException = HighNumberException
    deriving (Show, Eq, Typeable)

instance Exception HighNumberException

type Resource = MVar ()

acquireResource :: Resource -> IO Resource
acquireResource mvar = do
  takeMVar mvar
  return mvar

releaseResource :: Resource -> IO Resource
releaseResource mvar = do
  putMVar mvar ()
  return mvar

producerAct :: Int -> MVar Int -> IO ()
producerAct c mvar
  = case c > 10 of
      True -> throwIO HighNumberException
      False -> do putMVar mvar (c + 1)
                  producerAct (c + 1) mvar

consumerAct :: MVar Int -> IO ()
consumerAct mvar = do
  _ <- takeMVar mvar
  consumerAct mvar

fromActToJob :: Resource -> IO () -> IO ()
fromActToJob resource act = do
  bracket
    (acquireResource resource)
    (releaseResource)
    (\resource -> act)

coordinator1 :: [Resource] -> IO ()
coordinator1 [r1, r2] = do
  mvar <- newEmptyMVar
  withAsync (fromActToJob r1 (producerAct 0 mvar)) $ \p ->
    withAsync (fromActToJob r2 (consumerAct mvar)) $ \c -> do
      wait p
      wait c

coordinator2 :: [Resource] -> IO ()
coordinator2 [r1, r2] = do
  mvar <- newEmptyMVar
  withAsync (fromActToJob r1 (producerAct 0 mvar)) $ \p ->
    withAsync (fromActToJob r2 (consumerAct mvar)) $ \c -> do
      wait c
      wait p

coordinator3 :: [Resource] -> IO ()
coordinator3 [r1, r2] = do
  mvar <- newEmptyMVar
  withAsync (fromActToJob r1 (producerAct 0 mvar)) $ \p ->
    withAsync (fromActToJob r2 (consumerAct mvar)) $ \c -> do
      waitAll [p, c] []
  return ()

coordinator4 :: [Resource] -> IO ()
coordinator4 [r1, r2] = do
  mvar <- newEmptyMVar
  withAsync (fromActToJob r1 (producerAct 0 mvar)) $ \p ->
    withAsync (fromActToJob r2 (consumerAct mvar)) $ \c -> do
      waitAll [c, p] []
  return ()

-- | Wait termination of all supplied asynchronous threads.
--   The threads are considered children of the same parent thread,
--   so if one of the asynchronous thread fails raising an exception, also other asynchronous threads are cancelled.
--   Only the more informative exception is rethrown to the parent thread.
waitAll
    :: [Async a]
    -- ^ wait termination of threads
    -> [Async a]
    -- ^ do not wait the termination of these threads,
    -- but cancel them in case there is an exception in the monitored threads 
    -> IO [a]
waitAll allJobs otherJobs
  = w allJobs

  where

    w [] = (rights . catMaybes) <$> mapM poll allJobs

    w jobs1
      = catchAsync
          (do (job2, _) <- waitAny jobs1
              let jobs3 = L.filter ((/=) job2) jobs1
              w jobs3)
          (\(e :: SomeException)
               -> do exceptions <- (lefts . catMaybes) <$> mapM poll allJobs
                     let e3 = foldl' moreSpecificException e exceptions
                     mapM_ cancel $ allJobs ++ otherJobs
                     throwIO e3)

    moreSpecificException :: SomeException  -> SomeException -> SomeException
    moreSpecificException exc1 exc2
      = case cast  (toException exc2) of
          Just (_ :: BlockedIndefinitelyOnMVar)
            -> exc1
          Nothing
            -> case cast (toException exc2) of
                 Just (_ :: BlockedIndefinitelyOnSTM)
                   -> exc1
                 Nothing
                   -> if isSyncException exc2 then exc2 else exc1
                      -- NOTE: async exceptions are generated from external threads,
                      -- so they are less informative than synchronous exceptions.

-- | Return True if the more informative exception is catched.
testHighNumberException :: IO a -> IO Bool
testHighNumberException act
  = withAsync act $ \job ->
      (wait job >> return True)
        `catch` (\(e :: HighNumberException) -> return True)
          `catch` (\(e :: BlockedIndefinitelyOnMVar) -> return False)
            `catch` (\(e :: BlockedIndefinitelyOnSTM) -> return False)
              `catch` (\(e :: SomeException) -> do
                                putStrLn $ "Unrecognized exception: " ++ show e
                                return False)

-- | True if all resources are correctly released.
testReleasedResource :: [Resource] -> IO Bool
testReleasedResource resources = and <$> mapM isFullMVar resources
  where
    isFullMVar :: MVar a -> IO Bool
    isFullMVar mvar = not <$> isEmptyMVar mvar

showTest :: String -> ([Resource] -> IO a) -> [Resource] -> IO ()
showTest testName act resources = do

  e <- testHighNumberException (act resources)
  let ee = if e then "informative exception" else "generic BlockedIndefinitelyOnMVar excetpion"

  r <- testReleasedResource resources
  let rr = if r then "released all resources" else "some unreleased resources"

  putStrLn $ testName ++ ": exited with " ++ ee ++ ", and " ++ rr

main :: IO ()
main = do
  a1 <- newMVar ()
  a2 <- newMVar ()

  b1 <- newMVar ()
  b2 <- newMVar ()

  c1 <- newMVar ()
  c2 <- newMVar ()

  d1 <- newMVar ()
  d2 <- newMVar ()

  showTest "coordinator1" coordinator1 [a1, a2]
  showTest "coordinator2" coordinator2 [b1, b2]
  showTest "coordinator3" coordinator3 [c1, c2]
  showTest "coordinator4" coordinator4 [d1, d2]
