# blocked-on-mvar

## How to run

```
stack build --fast

stack exec blocked-on-mvar-exe

> blocked-on-mvar-exe: thread blocked indefinitely in an STM transaction
```

## The problem

The producer send the informative exception ``HighNumberException``, but the ``coordinator`` job receives a generic ``BlockedIndefinitelyOnMVar``, because the producer stop working.

How can I discard the generic exception, and manage only ``HighNumberException``?
