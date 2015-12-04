{- git-annex repository versioning
 -
 - Copyright 2010,2013 Joey Hess <id@joeyh.name>
 -
 - Licensed under the GNU GPL version 3 or higher.
 -}

{-# LANGUAGE CPP #-}

module Annex.Version where

import Common.Annex
import Config
import qualified Annex

type Version = String

currentVersion :: Version
currentVersion = "6"

supportedVersions :: [Version]
supportedVersions = ["5", currentVersion]

upgradableVersions :: [Version]
#ifndef mingw32_HOST_OS
upgradableVersions = ["0", "1", "2", "4", "5"]
#else
upgradableVersions = ["2", "3", "4", "5"]
#endif

autoUpgradeableVersions :: [Version]
autoUpgradeableVersions = ["3", "4"]

versionField :: ConfigKey
versionField = annexConfig "version"

getVersion :: Annex (Maybe Version)
getVersion = annexVersion <$> Annex.getGitConfig

setVersion :: Version -> Annex ()
setVersion = setConfig versionField

removeVersion :: Annex ()
removeVersion = unsetConfig versionField
