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
```

The producer send the informative exception ``HighNumberException``, but the ``coordinator`` job receives a generic ``BlockedIndefinitelyOnMVar``, because the producer stop working.

How can I discard the generic exception, and re-throw/catch only ``HighNumberException``?
