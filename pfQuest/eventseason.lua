-- pfQuest event/seasonal quest classification and scheduling.
--
-- Three event subtypes, driven by octowow.st Seasonal-category membership plus
-- the scrape's repeatable flag:
--   "unique"     (gold)   : completed permanently; never resets.
--   "annual"     (orange) : completed now, but resets to available each time its
--                           event begins again. This is the DEFAULT for seasonal
--                           quests that are not flagged repeatable, because
--                           recurring holidays are the common case.
--   "repeatable" (blue)   : never marked completed; always available.
--
-- The scrape cannot distinguish Unique from Annual (no annual flag on the
-- site), so non-repeatable seasonal quests default to Annual and individual
-- quests are overridden to Unique in pfQuestEventUniqueOverrides below.
--
-- Event scheduling: each named event has an `ongoing` flag and an optional
-- start time. The mechanism is dynamic (events can begin/end while the player
-- is online) and is currently mocked to infinitely-ongoing; real dates get
-- filled in per event later. When an event transitions not-ongoing -> ongoing,
-- Annual quests belonging to it are reset (removed from pfQuest_history).

pfQuestEvent = pfQuestEvent or {}

-- ---------------------------------------------------------------------------
-- Event definitions. questids belong to an event; the event has a schedule.
-- Mock: ongoing = true (infinitely ongoing) until real dates are added.
-- `start`/`stop` are reserved for real calendar dates (epoch seconds); while
-- they are nil the event is treated as ongoing iff `ongoing` is true.
-- ---------------------------------------------------------------------------
pfQuestEvent.events = {
  -- example:
  -- midsummer = { ongoing = true, start = nil, stop = nil, quests = { 9324, 9325, ... } },
}

-- quests overridden from the Annual default to Unique (complete-once).
pfQuestEvent.uniqueOverrides = {
  -- [9324] = true,
}

-- Populate event->quest membership from the scraped seasonal set (filled by
-- overwrites.lua into pfQuestEvent.seasonalQuests). Membership classification:
--   repeatable flag set  -> "repeatable"
--   in uniqueOverrides   -> "unique"
--   otherwise            -> "annual"
function pfQuestEvent:Subtype(questid)
  if not self.seasonalQuests or not self.seasonalQuests[questid] then
    return nil -- not an event/seasonal quest
  end
  local q = pfDB and pfDB["quests"] and pfDB["quests"]["data"] and pfDB["quests"]["data"][questid]
  if q and q["repeatable"] then
    return "repeatable"
  end
  if self.uniqueOverrides[questid] then
    return "unique"
  end
  return "annual"
end

-- Which event (if any) a quest belongs to.
function pfQuestEvent:EventForQuest(questid)
  for name, ev in pairs(self.events) do
    if ev.quests then
      for _, qid in pairs(ev.quests) do
        if qid == questid then
          return name, ev
        end
      end
    end
  end
  return nil, nil
end

-- Is the given event currently ongoing? Mock: `ongoing` flag, since start/stop
-- dates are not yet populated.
function pfQuestEvent:IsOngoing(eventName)
  local ev = self.events[eventName]
  if not ev then
    return true, nil -- unknown events are treated as ongoing for now
  end
  local now = time and time() or 0
  if ev.start and now < ev.start then
    return false, ev
  end
  if ev.stop and now >= ev.stop then
    return false, ev
  end
  return ev.ongoing and true or false, ev
end

-- For a given event quest: should it be shown right now?
-- Returns true (show), false (hide).
function pfQuestEvent:ShouldShow(questid)
  local subtype = self:Subtype(questid)
  if not subtype then
    return true -- not an event quest; let normal filter decide
  end

  local eventName, ev = self:EventForQuest(questid)
  local ongoing = true
  if eventName then
    ongoing = self:IsOngoing(eventName)
  end

  if subtype == "repeatable" then
    -- always available (subject to event being ongoing, if we track it)
    return ongoing
  end

  local completed = pfQuest_history and pfQuest_history[questid] and true or false
  if subtype == "unique" then
    -- completed permanently -> never show again
    return not completed
  end

  -- annual: available when the event is ongoing and not yet completed this run
  if not ongoing then
    return false
  end
  return not completed
end

-- Called when an event begins again (not-ongoing -> ongoing). Resets Annual
-- quests belonging to it so they become available for the new occurrence.
function pfQuestEvent:OnEventBegin(eventName)
  local ev = self.events[eventName]
  if not ev or not ev.quests then
    return
  end
  for _, qid in pairs(ev.quests) do
    if self:Subtype(qid) == "annual" and pfQuest_history then
      pfQuest_history[qid] = nil
    end
  end
  if pfQuest and pfQuest.ResetAll then
    pfQuest:ResetAll()
  end
end

-- Watch for event transitions. Currently a stub driver: since all events are
-- mocked infinitely-ongoing, nothing changes. Once real start/stop dates are
-- added, this polls and fires OnEventBegin on the not-ongoing->ongoing edge.
pfQuestEvent.lastOngoing = {}
local frame = CreateFrame("Frame", "pfQuestEventFrame", UIParent)
frame.elapsed = 0
frame:SetScript("OnUpdate", function()
  this.elapsed = (this.elapsed or 0) + arg1
  if this.elapsed < 5 then
    return
  end
  this.elapsed = 0
  for name, ev in pairs(pfQuestEvent.events) do
    local ongoing = pfQuestEvent:IsOngoing(name)
    local was = pfQuestEvent.lastOngoing[name]
    if ongoing and was == false then
      pfQuestEvent:OnEventBegin(name)
    end
    pfQuestEvent.lastOngoing[name] = ongoing
  end
end)
