module Hp.Event.AnswerPoll where

import Hp.Poll         (PollId)
import Hp.PollAnswer   (PollAnswer)
import Hp.PollAnswerId (PollAnswerId)
import Hp.UserId       (UserId)


-- | A poll was answered.
data AnswerPollEvent
  = AnswerPollEvent
  { answer :: PollAnswer
  , id :: PollAnswerId
  , pollId :: PollId
  , userId :: Maybe UserId
  } deriving stock (Generic, Show)
