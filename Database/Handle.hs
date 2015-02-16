{- Persistent sqlite database handles.
 -
 - Copyright 2015 Joey Hess <id@joeyh.name>
 -
 - Licensed under the GNU GPL version 3 or higher.
 -}

module Database.Handle (
	DbHandle,
	openDb,
	runDb,
	CommitPolicy(..),
	runDb',
	commitDb,
	closeDb,
) where

import Utility.Exception

import Database.Persist.Sqlite (runSqlite)
import Database.Esqueleto hiding (Key)
import Control.Monad
import Control.Monad.IO.Class (liftIO)
import Control.Concurrent
import Control.Concurrent.Async
import Control.Exception (throwIO)
import qualified Data.Text as T
import Data.Time.Clock

{- A DbHandle is a reference to a worker thread that communicates with
 - the database. It has a MVar which Jobs are submitted to. -}
data DbHandle = DbHandle (Async ()) (MVar Job) (MVar UTCTime)

data Job = RunJob (SqlPersistM ()) | CommitJob | CloseJob

openDb :: FilePath -> IO DbHandle
openDb db = do
	jobs <- newEmptyMVar
	worker <- async (workerThread (T.pack db) jobs)
	t <- newMVar =<< getCurrentTime
	return $ DbHandle worker jobs t

workerThread :: T.Text -> MVar Job -> IO ()
workerThread db jobs = go
  where
	go = do
		r <- runSqlite db transaction
		case r of
			CloseJob -> return ()
			_ -> go
	transaction = do
		job <- liftIO $ takeMVar jobs
		case job of
			RunJob a -> a >> transaction
			CommitJob -> return CommitJob
			CloseJob -> return CloseJob


{- Runs an action using the DbHandle.
 -
 - Note that the action is not run by the calling thread, but by a
 - worker thread. Exceptions are propigated to the calling thread.
 -
 - Only one action can be run at a time against a given DbHandle.
 - If called concurrently, this will block until it is able to run.
 -}
runDb :: DbHandle -> SqlPersistM a -> IO a
runDb h = runDb' h CommitManually

data CommitPolicy = CommitManually | CommitAfter NominalDiffTime

runDb' :: DbHandle -> CommitPolicy -> SqlPersistM a -> IO a
runDb' h@(DbHandle _ jobs t) pol a = do
	res <- newEmptyMVar
	putMVar jobs $ RunJob $ liftIO . putMVar res =<< tryNonAsync a
	r <- either throwIO return =<< takeMVar res
	case pol of
		CommitManually -> return ()
		CommitAfter n -> do
			now <- getCurrentTime
			prev <- takeMVar t
			putMVar t now
			when (diffUTCTime now prev > n) $
				commitDb h
	return r

{- Commits any transaction that was created by the previous calls to runDb,
 - and starts a new transaction. -}
commitDb :: DbHandle -> IO ()
commitDb (DbHandle _ jobs _) = putMVar jobs CommitJob

closeDb :: DbHandle -> IO ()
closeDb (DbHandle worker jobs _) = do
	putMVar jobs CloseJob
	wait worker
