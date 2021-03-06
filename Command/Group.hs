{- git-annex command
 -
 - Copyright 2012 Joey Hess <id@joeyh.name>
 -
 - Licensed under the GNU AGPL version 3 or higher.
 -}

module Command.Group where

import Command
import qualified Remote
import Logs.Group
import Types.Group

import qualified Data.Set as S

cmd :: Command
cmd = noMessages $ command "group" SectionSetup "add a repository to a group"
	(paramPair paramRemote paramDesc) (withParams seek)

seek :: CmdParams -> CommandSeek
seek = withWords (commandAction . start)

start :: [String] -> CommandStart
start (name:g:[]) = do
	allowMessages
	showStart' "group" (Just name)
	u <- Remote.nameToUUID name
	next $ setGroup u (toGroup g)
start (name:[]) = do
	u <- Remote.nameToUUID name
	liftIO . putStrLn . unwords . map fmt . S.toList =<< lookupGroups u
	stop
  where
	fmt (Group g) = decodeBS g
start _ = giveup "Specify a repository and a group."

setGroup :: UUID -> Group -> CommandPerform
setGroup uuid g = do
	groupChange uuid (S.insert g) 
	next $ return True
