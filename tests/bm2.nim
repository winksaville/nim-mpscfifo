import msg, linknode, mpscfifo, msgarena, msglooper, benchmark, os, locks

# include bmSuite so we can use it inside t(name: string)
include "bmsuite"

const
  runTime = 2.00 #30.0
  warmupTime = 0.0 #0.25
  threadCount = 1
  testStatsCount = 1

var
  ma: MsgArenaPtr
  ml1: MsgLooperPtr
  ml1RsvQ: QueuePtr

var
  ml1PmCount = 0
proc ml1Pm(msg: MsgPtr) =
  echo "ml1Pm: **** msg=", msg
  ml1PmCount += 1
  msg.rspq.add(msg)

ma = newMsgArena()
ml1 = newMsgLooper("ml1")
ml1RsvQ = newMpscFifo("ml1RsvQ", ma)
ml1.addProcessMsg(ml1Pm, ml1RsvQ)

type
  TObj = object
    name: string
    index: int32

proc newTObj(name: string, index: int): TObj =
  result.name = name
  result.index = cast[int32](index and 0xFFFFFFFF)

proc t(tobj: TObj) {.thread.} =
  echo "t+ tobj=", tobj

  bmSuite tobj.name, warmupTime:
    echo suiteObj.suiteName & ".suiteObj=" & $suiteObj
    var
      msg: MsgPtr
      rspq: QueuePtr
      tsa: array[0..testStatsCount-1, TestStats]

    setup:
      rspq = newMpscFifo("rspq-" & suiteObj.suiteName, ma)
      msg = ma.getMsg(tobj.index, 0)
      msg.rspq = rspq

    teardown:
      ma.retMsg(msg)
      rspq.delMpscFifo()

    # One loop for the moment
    test "ping-pong", 1, tsa: #runTime, tsa:
      ml1RsvQ.add(msg)
      echo "waiting for response!!"
      while true:
        msg = rspq.rmv()
        if msg != nil:
          break

  echo "t:- tobj=", tobj

var
  idx = 0
  threads: array[0..threadCount-1, TThread[TObj]]

for idx in 0..threads.len-1:
  var tobj = newTObj("X" & $idx, idx)
  createThread[TObj](threads[idx], t, tobj)

sleep(round(runTime * 1000.0 * 1.20))

echo "cleanup ml1PmCount=", ml1PmCount

ml1RsvQ.delMpscFifo()
ml1.delMsgLooper()
ma.delMsgArena()