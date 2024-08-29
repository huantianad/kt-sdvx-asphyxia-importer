import std/[syncio, sequtils, strformat, strutils, rdstdin, sets, options]
import pkg/jsony

type
  BatchManual = object
    meta: BatchManualMeta
    scores: seq[BatchManualScore]
    classes: Option[BatchManualClasses]

  BatchManualMeta = object
    game: string
    playtype: string
    service: string
    version: string

  BatchManualScore = object
    score: int
    lamp: Lamp
    matchType: string
    identifier: string
    difficulty: Difficulty
    timeAchieved: int
    optional: BatchManualSdvx

  BatchManualSdvx = object
    exScore: int

  BatchManualClasses = object
    dan: Dan

  Lamp = enum
    Invalid
    Failed
    Clear
    ExcessiveClear
    UltimateChain
    PerfectUltimateChain

  Difficulty = enum
    Nov
    Adv
    Exh
    AnyInf
    Mxm

  Dan = enum
    Unset
    Dan1
    Dan2
    Dan3
    Dan4
    Dan5
    Dan6
    Dan7
    Dan8
    Dan9
    Dan10
    Dan11
    Inf

  EntryType = enum
    item
    music
    param
    course
    profile
    arena
    skill

  Entry = object
    profileId: string
    case kind: EntryType
    of item: discard
    of param: discard
    of course: discard
    of profile:
      name: string
    of arena: discard
    of skill:
      base, level, danName: Dan
    of music:
      musicId: int
      difficulty: Difficulty
      score: int
      exscore: int
      clear: Lamp
      grade, buttonRate, longRate, volRate: int
      createdAt, updatedAt: WeirdDate

  WeirdDate = object
    date: int

const ignoredSongs = [1759, 1760, 1761, 1874]
const batchMetadata = BatchManualMeta(
  game: "sdvx", playtype: "Single", service: "Asphyxia CORE", version: "exceed"
)

proc renameHook*(v: var WeirdDate, fieldName: var string) =
  if fieldName == "$$date":
    fieldName = "date"

proc renameHook*(v: var Entry, fieldName: var string) =
  if fieldName == "collection":
    fieldName = "kind"
  elif fieldname == "mid":
    fieldname = "musicId"
  elif fieldName == "type":
    fieldName = "difficulty"
  elif fieldName == "__refid":
    fieldName = "profileId"

  if v.kind == skill and fieldName == "name":
    fieldName = "danName"

proc dumpHook*(s: var string, v: Lamp) =
  assert v != Invalid
  s.add '"'
  s.add [
    Invalid: "", "FAILED", "CLEAR", "EXCESSIVE CLEAR", "ULTIMATE CHAIN",
    "PERFECT ULTIMATE CHAIN",
  ][v]
  s.add '"'

proc dumpHook*(s: var string, v: Difficulty) =
  s.add '"'
  s.add [Nov: "NOV", "ADV", "EXH", "ANY_INF", "MXM"][v]
  s.add '"'

proc dumpHook*(s: var string, v: Dan) =
  s.add '"'
  case v
  of Unset:
    assert false
  of Dan1 .. Dan11:
    s.add "DAN_"
    s.add $v.ord()
  of Inf:
    s.add "INF"
  s.add '"'

proc promptProfiles(profiles: seq[Entry]): HashSet[string] =
  echo "Available profiles:"
  for i, profile in profiles:
    echo fmt"{i}: {profile.name}"

  while true:
    let input = readLineFromStdin(
      "Enter comma seperated list of indexes, or 'all' to select all: "
    )
    if input == "all":
      return profiles.mapIt(it.profileId).toHashSet

    try:
      return input.strip().split(",").mapIt(profiles[parseInt(it)].profileId).toHashSet
    except:
      echo "Invalid input!"

proc main() =
  var profiles: seq[Entry]
  var songs: seq[Entry]
  var skills: seq[Entry]

  for line in "sdvx@asphyxia.db".lines:
    let entry = line.fromJson(Entry)
    case entry.kind
    of profile:
      profiles.add entry
    of music:
      if entry.clear != Invalid and entry.musicId notin ignoredSongs:
        songs.add entry
    of skill:
      skills.add entry
    else:
      discard

  let selectedProfiles = promptProfiles(profiles)

  var output = BatchManual(meta: batchMetadata, classes: some(BatchManualClasses()))

  for entry in songs:
    if entry.profileId in selectedProfiles:
      output.scores.add BatchManualScore(
        score: entry.score,
        lamp: entry.clear,
        matchType: "sdvxInGameID",
        identifier: $entry.musicId,
        difficulty: entry.difficulty,
        timeAchieved: entry.updatedAt.date,
        optional: BatchManualSdvx(exScore: entry.exscore),
      )

  for entry in skills:
    if entry.profileId in selectedProfiles:
      assert entry.base == entry.level
      assert entry.base == entry.danName
      if entry.base > output.classes.get().dan:
        output.classes.get().dan = entry.base

  if output.classes.get().dan == Unset:
    output.classes = none(BatchManualClasses)

  writeFile("output.json", output.toJson)

if isMainModule:
  main()
