{- Web url logs.
 -
 - Copyright 2011-2014 Joey Hess <id@joeyh.name>
 -
 - Licensed under the GNU GPL version 3 or higher.
 -}

module Logs.Web (
	URLString,
	getUrls,
	getUrlsWithPrefix,
	setUrlPresent,
	setUrlMissing,
	knownUrls,
	Downloader(..),
	getDownloader,
	setDownloader,
	setTempUrl,
	removeTempUrl,
) where

import qualified Data.ByteString.Lazy.Char8 as L
import qualified Data.Map as M
import Data.Tuple.Utils

import Common.Annex
import qualified Annex
import Logs
import Logs.Presence
import Logs.Location
import qualified Annex.Branch
import Annex.CatFile
import qualified Git
import qualified Git.LsFiles
import Utility.Url

{- Gets all urls that a key might be available from. -}
getUrls :: Key -> Annex [URLString]
getUrls key = do
	l <- go $ urlLogFile key : oldurlLogs key
	tmpl <- Annex.getState (maybeToList . M.lookup key . Annex.tempurls)
	return (tmpl ++ l)
  where
	go [] = return []
	go (l:ls) = do
		us <- currentLog l
		if null us
			then go ls
			else return us

getUrlsWithPrefix :: Key -> String -> Annex [URLString]
getUrlsWithPrefix key prefix = filter (prefix `isPrefixOf`) <$> getUrls key

setUrlPresent :: UUID -> Key -> URLString -> Annex ()
setUrlPresent uuid key url = do
	us <- getUrls key
	unless (url `elem` us) $
		addLog (urlLogFile key) =<< logNow InfoPresent url
	logChange key uuid InfoPresent

setUrlMissing :: UUID -> Key -> URLString -> Annex ()
setUrlMissing uuid key url = do
	addLog (urlLogFile key) =<< logNow InfoMissing url
	whenM (null <$> getUrls key) $
		logChange key uuid InfoMissing

{- Finds all known urls. -}
knownUrls :: Annex [URLString]
knownUrls = do
	{- Ensure the git-annex branch's index file is up-to-date and
	 - any journaled changes are reflected in it, since we're going
	 - to query its index directly. -}
	Annex.Branch.update
	Annex.Branch.commit "update"
	Annex.Branch.withIndex $ do
		top <- fromRepo Git.repoPath
		(l, cleanup) <- inRepo $ Git.LsFiles.stagedDetails [top]
		r <- mapM (geturls . snd3) $ filter (isUrlLog . fst3) l
		void $ liftIO cleanup
		return $ concat r
  where
	geturls Nothing = return []
	geturls (Just logsha) = getLog . L.unpack <$> catObject logsha

setTempUrl :: Key -> URLString -> Annex ()
setTempUrl key url = Annex.changeState $ \s ->
	s { Annex.tempurls = M.insert key url (Annex.tempurls s) }

removeTempUrl :: Key -> Annex ()
removeTempUrl key = Annex.changeState $ \s ->
	s { Annex.tempurls = M.delete key (Annex.tempurls s) }

data Downloader = WebDownloader | QuviDownloader | OtherDownloader
	deriving (Eq)

{- To keep track of how an url is downloaded, it's mangled slightly in
 - the log. For quvi, "quvi:" is prefixed. For urls that are handled by
 - some other remote, ":" is prefixed. -}
setDownloader :: URLString -> Downloader -> String
setDownloader u WebDownloader = u
setDownloader u QuviDownloader = "quvi:" ++ u
setDownloader u OtherDownloader = ":" ++ u

getDownloader :: URLString -> (URLString, Downloader)
getDownloader u = case separate (== ':') u of
	("quvi", u') -> (u', QuviDownloader)
	("", u') -> (u', OtherDownloader)
	_ -> (u, WebDownloader)
