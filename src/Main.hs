module Main where

import Control.Exception.Safe
import Control.Concurrent.Async
import Control.Concurrent.MVar

data HighNumberException = HighNumberException
    deriving Show

instance Exception HighNumberException

producer :: Int -> MVar Int -> IO ()
producer c mvar
  = case c > 10 of
      True -> throwIO HighNumberException
      False -> do putMVar mvar (c + 1)
                  producer (c + 1) mvar

consumer :: MVar Int -> IO ()
consumer mvar = do
  _ <- takeMVar mvar
  consumer mvar

coordinator :: MVar Int -> IO ()
coordinator mvar = do
  withAsync (producer 0 mvar) $ \p ->  
    withAsync (consumer mvar) $ \c -> do
      wait c
      wait p

main :: IO ()
main = do
  mvar <- newEmptyMVar
  withAsync (coordinator mvar) (wait) 
  putStrLn "done"

