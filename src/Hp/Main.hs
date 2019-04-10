{-# LANGUAGE AllowAmbiguousTypes #-}

{-# OPTIONS_GHC -fno-warn-partial-type-signatures #-}

module Hp.Main where

import Hp.API
import Hp.Config                      (Config(..), prettyPrintConfig,
                                       readConfigFile)
import Hp.Eff.Await.Chan              (runAwaitChan)
import Hp.Eff.DB                      (runDBC)
import Hp.Eff.GitHubAuth.Http         (runGitHubAuthHttp)
import Hp.Eff.HttpRequest.IO          (runHttpRequestIO)
import Hp.Eff.HttpSession.IO          (runHttpSessionIO)
import Hp.Eff.PersistPoll.DB          (PersistPollDBC(..))
import Hp.Eff.PersistPollAnswer.DB    (runPersistPollAnswerDB)
import Hp.Eff.PersistUser.DB          (runPersistUserDB)
import Hp.Eff.Yield.Chan              (runYieldChan)
import Hp.Email                       (Email)
import Hp.Event.PollAnswered          (PollAnsweredEvent)
import Hp.Event.PollCreated           (PollCreatedEvent)
import Hp.GitHub.ClientId             (GitHubClientId)
import Hp.GitHub.ClientSecret         (GitHubClientSecret)
import Hp.Handler.AnswerPoll          (handleAnswerPoll)
import Hp.Handler.CreatePoll          (handleCreatePoll)
import Hp.Handler.GetMetrics          (handleGetMetrics)
import Hp.Handler.GetRoot             (handleGetRoot)
import Hp.Handler.GitHubOauthCallback (handleGitHubOauthCallback)
import Hp.Metrics                     (requestCounter)
import Hp.PostgresConfig              (acquirePostgresPool)
import Hp.Worker.SendPollCreatedEmail (sendPollCreatedEmailWorker)

import Control.Concurrent     (forkIO)
import Control.Concurrent.STM
import Control.Effect
-- import Control.Effect.Error
-- import Control.Monad.Trans.Except (ExceptT(..))
import Servant     (Context((:.)))
import System.Exit (exitFailure)

import qualified Data.Text.IO             as Text
import qualified Hasql.Pool               as Hasql (Pool)
import qualified Network.HTTP.Client      as Http
import qualified Network.HTTP.Client.TLS  as Http (tlsManagerSettings)
import qualified Network.Wai              as Wai
import qualified Network.Wai.Handler.Warp as Warp
import qualified Prometheus
import qualified Servant
import qualified Servant.Client           as Servant (ClientError)
import qualified Servant.Server.Generic   as Servant (genericServeTWithContext)
import qualified SlaveThread

import Servant.Auth.Server as Servant


main :: IO ()
main = do
  config :: Config <-
    readConfigFile "./config.dhall" >>= \case
      Left errs -> do
        for_ errs Text.putStrLn
        exitFailure

      Right config ->
        pure config

  prettyPrintConfig config

  httpManager :: Http.Manager <-
    Http.newManager Http.tlsManagerSettings

  jwtSettings :: JWTSettings <-
    either id pure (config ^. #session . #jwt)

  pgPool <- acquirePostgresPool (config ^. #postgres)

  pollAnsweredEventChan :: TChan PollAnsweredEvent <-
    atomically newBroadcastTChan

  pollCreatedEventChan :: TChan PollCreatedEvent <-
    atomically newBroadcastTChan

  emailChan :: TChan Email <-
    atomically newBroadcastTChan

  void . SlaveThread.fork $ do
    chan :: TChan PollCreatedEvent <-
      atomically (dupTChan pollCreatedEventChan)

    sendPollCreatedEmailWorker
      & runAwaitChan chan
      & runPersistUserDB
      & runDBC pgPool
      & runYieldChan emailChan
      & runM

  do
    -- Lazy! Just print these events forever
    let go eventChan =
          void . forkIO $ do
            chan <- atomically (dupTChan eventChan)
            forever (atomically (readTChan chan) >>= print)
    go pollAnsweredEventChan
    go pollCreatedEventChan

  Warp.run
    (fromIntegral (config ^. #port))
    (middleware
      (application
        (config ^. #session . #cookie)
        (config ^. #gitHub . #clientId)
        (config ^. #gitHub . #clientSecret)
        httpManager
        jwtSettings
        pgPool
        pollAnsweredEventChan
        pollCreatedEventChan))

middleware ::
     (  Wai.Request
     -> (Wai.Response -> IO Wai.ResponseReceived)
     -> IO Wai.ResponseReceived)
  -> Wai.Request
  -> (Wai.Response -> IO Wai.ResponseReceived)
  -> IO Wai.ResponseReceived
middleware app request respond = do
  Prometheus.incCounter requestCounter
  app request respond

application ::
     CookieSettings
  -> GitHubClientId
  -> GitHubClientSecret
  -> Http.Manager
  -> JWTSettings
  -> Hasql.Pool
  -> TChan PollAnsweredEvent
  -> TChan PollCreatedEvent
  -> Wai.Request
  -> (Wai.Response -> IO Wai.ResponseReceived)
  -> IO Wai.ResponseReceived
application
    cookieSettings
    gitHubClientId
    gitHubClientSecret
    httpManager
    jwtSettings
    postgresPool
    pollAnsweredEventChan
    pollCreatedEventChan = do

  Servant.genericServeTWithContext
    η
    API
      { answerPollRoute = handleAnswerPoll
      , createPollRoute = handleCreatePoll
      , getRootRoute = handleGetRoot
      , getMetricsRoute = handleGetMetrics
      , gitHubOauthCallbackRoute = handleGitHubOauthCallback
      }
    (cookieSettings
      :. jwtSettings
      :. Servant.EmptyContext)

  where
    η :: ∀ a. _ a -> Servant.Handler a
    η =   -- Outgoing HTTP requests
          runGitHubAuthHttp gitHubClientId gitHubClientSecret
      >>> runHttpRequestIO httpManager

          -- Persistence layer
      >>> unPersistPollDBC
      >>> runPersistPollAnswerDB
      >>> runPersistUserDB
      >>> runDBC postgresPool

          -- HTTP session
      >>> runHttpSessionIO cookieSettings jwtSettings

          -- Event handlers
      >>> runYieldChan pollAnsweredEventChan
      >>> runYieldChan pollCreatedEventChan

          -- IO boilerplate
      >>> runM @IO
      >>> liftIO
      >>> Servant.Handler


-- TODO Generalize to ApplicationException
-- TODO Implement toServerError
toServerError
  :: Servant.ClientError
  -> Servant.ServerError
toServerError = undefined
