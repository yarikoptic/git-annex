{- git-annex command
 -
 - Copyright 2010-2014 Joey Hess <id@joeyh.name>
 -
 - Licensed under the GNU AGPL version 3 or higher.
 -}

{-# LANGUAGE CPP #-}

module Command.PreCommit where

import Command
import qualified Command.Add
import qualified Command.Fix
import qualified Command.Smudge
import Annex.Hook
import Annex.Link
import Annex.View
import Annex.Version
import Annex.View.ViewedFile
import Annex.LockFile
import Logs.View
import Logs.MetaData
import Types.View
import Types.MetaData
import qualified Git.Index as Git
import qualified Git.LsFiles as Git

import qualified Data.Set as S
import qualified Data.Text as T

cmd :: Command
cmd = command "pre-commit" SectionPlumbing
	"run by git pre-commit hook"
	paramPaths
	(withParams seek)

seek :: CmdParams -> CommandSeek
seek ps = lockPreCommitHook $ do
	ifM (not <$> versionSupportsUnlockedPointers <&&> liftIO Git.haveFalseIndex)
		( do
			(fs, cleanup) <- inRepo $ Git.typeChangedStaged ps
			whenM (anyM isOldUnlocked fs) $
				giveup "Cannot make a partial commit with unlocked annexed files. You should `git annex add` the files you want to commit, and then run git commit."
			void $ liftIO cleanup
		, do
			l <- workTreeItems ps
			-- fix symlinks to files being committed
			flip withFilesToBeCommitted l $ \f -> commandAction $
				maybe stop (Command.Fix.start Command.Fix.FixSymlinks f)
					=<< isAnnexLink f
			ifM versionSupportsUnlockedPointers
				-- after a merge conflict or git
				-- cherry-pick or stash, pointer
				-- files in the worktree won't
				-- be populated, so populate them
				-- here
				( Command.Smudge.updateSmudged (Restage False)
				-- inject unlocked files into the annex
				-- (not needed when repo version uses
				-- unlocked pointer files)
				, withFilesOldUnlockedToBeCommitted (commandAction . startInjectUnlocked) l
				)
		)
	
	runAnnexHook preCommitAnnexHook

	-- committing changes to a view updates metadata
	mv <- currentView
	case mv of
		Nothing -> noop
		Just v -> withViewChanges
			(addViewMetaData v)
			(removeViewMetaData v)

startInjectUnlocked :: FilePath -> CommandStart
startInjectUnlocked f = startingCustomOutput (ActionItemOther Nothing) $ do
	unlessM (callCommandAction $ Command.Add.start f) $
		error $ "failed to add " ++ f ++ "; canceling commit"
	next $ return True

addViewMetaData :: View -> ViewedFile -> Key -> CommandStart
addViewMetaData v f k = starting "metadata" (mkActionItem (k, f)) $
	next $ changeMetaData k $ fromView v f

removeViewMetaData :: View -> ViewedFile -> Key -> CommandStart
removeViewMetaData v f k = starting "metadata" (mkActionItem (k, f)) $
	next $ changeMetaData k $ unsetMetaData $ fromView v f

changeMetaData :: Key -> MetaData -> CommandCleanup
changeMetaData k metadata = do
	showMetaDataChange metadata
	addMetaData k metadata
	return True

showMetaDataChange :: MetaData -> Annex ()
showMetaDataChange = showLongNote . unlines . concatMap showmeta . fromMetaData
  where
	showmeta (f, vs) = map (showmetavalue f) $ S.toList vs
	showmetavalue f v = T.unpack (fromMetaField f) <> showset v <> "=" <> decodeBS (fromMetaValue v)
	showset v
		| isSet v = "+"
		| otherwise = "-"

{- Takes exclusive lock; blocks until available. -}
lockPreCommitHook :: Annex a -> Annex a
lockPreCommitHook = withExclusiveLock gitAnnexPreCommitLock
