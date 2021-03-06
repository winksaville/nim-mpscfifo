## Types for msglooper.
##
## This was needed because there is a circular relationship
## between mpscfifo and msglooper.
import msg, msgarena, locks

const
  listMsgProcessorMaxLen* = 10

type
  MsgProcessorState* = enum
    empty, busy, adding, added, deleting

  MsgProcessorPtr* = ptr MsgProcessor
  MsgProcessor* = object
    state*: MsgProcessorState
    pm*: ProcessMsg
    mq*: QueuePtr
    cp*: ComponentPtr
    rspq*: QueuePtr
    newComponent*: NewComponent
    delComponent*: DelComponent

  NewComponent* = proc(ml: MsgLooperPtr): ComponentPtr
  DelComponent* = proc(cp: ComponentPtr)

  MsgLooperPtr* = ptr MsgLooper
  MsgLooper* = object
    name*: string
    initialized*: bool
    done*: bool
    condBool* : ptr bool
    cond*: ptr TCond
    lock*: ptr TLock
    ma*: MsgArenaPtr
    listMsgProcessorLen*: int
    listMsgProcessor*: ptr array[0..listMsgProcessorMaxLen-1,
        MsgProcessorPtr]
    thread*: ptr TThread[MsgLooperPtr]

