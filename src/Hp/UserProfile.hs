module Hp.UserProfile where

import Hp.GitHub.UserName (GitHubUserName)

import Data.Aeson (ToJSON)


data UserProfile
  = UserProfile
  { gitHub :: Maybe GitHubUserName
  } deriving stock (Generic)
    deriving anyclass (ToJSON)
