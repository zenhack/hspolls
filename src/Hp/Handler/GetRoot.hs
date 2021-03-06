module Hp.Handler.GetRoot
  ( handleGetRoot
  ) where

import Hp.Entity (Entity)
import Hp.User   (User)

import Control.Effect
import Prelude                     hiding (div)
import Servant.Auth.Server         (AuthResult(..))
import Text.Blaze.Html5
import Text.Blaze.Html5.Attributes


handleGetRoot ::
     ( Carrier sig m
     )
  => AuthResult (Entity User)
  -> m Html
handleGetRoot auth =
  (pure . fold)
    [ div ("Hello, world! You are: " <> toHtml (show auth))
      -- TODO set state get param
      -- TODO set redirect_uri get param
    , a "Log in with GitHub" !
        href
          (unsafeByteStringValue
            (fold
              [ "https://github.com/login/oauth/authorize?"
              , "allow_signup=false&"
              , "client_id=0708940f1632f7a953e8"
              ]))
    ]
