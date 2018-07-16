# blocked-on-mvar

## How to run

```
stack build --fast

stack exec blocked-on-mvar-exe

> blocked-on-mvar-exe: thread blocked indefinitely in an STM transaction
```

## The problem

Inside the code ``src/Main.hs``

```
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
```

The producer send the informative exception ``HighNumberException``, but the ``coordinator`` job receives a generic ``BlockedIndefinitelyOnMVar``, because the producer stop working.

## The solution

I defined this function waiting for the termination of all threads, and returning the most informative exception. 
In particular synchronous exceptions are favoured respect asynchronous exceptions, because synchronous exceptions
are generated from the processing code, and not from other threads or the run-time system.

```
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
```

I defined also ``withResource`` that is a bracket-like function, useful for seding informative exceptions to the user, and that plays niclely with `waitLL``. 
