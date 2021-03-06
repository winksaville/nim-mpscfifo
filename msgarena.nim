## The MsgArena manages getting and returning message from memory
## in a thread safe manner and so maybe shared by multipel threads.
##
## TODO: Add tests
## TODO: Using mpmcstack is lock-free but not wait-free, use mpscfifo?
import msg, mpmcstack, fifoutils, locks, strutils

const
  DBG = false
  msgArenaSize = 32

type
  MsgArenaPtr* = ptr MsgArena
  MsgArena* = object
    #lock: TLock
    msgStack: StackPtr

proc `$`*(ma: MsgArenaPtr): string =
  if ma == nil:
    result = "<nil>"
  else:
    #ma.lock.acquire()
    block:
      var msgStr = "{"
      var firstTime = true
      var sep = ""
      if ma.msgStack != nil:
        for ln in ma.msgStack:
          msgStr &= sep & $ln
          if firstTime:
            firstTime = false
            sep = ", "
      msgStr &= "}"
      result = "msgStack: " & " " & msgStr & "}"
    #ma.lock.release()

converter toMsg*(p: pointer): MsgPtr {.inline.} =
  result = cast[MsgPtr](p)

proc initMsg(msg: MsgPtr, next: MsgPtr, rspq: QueuePtr, cmdVal: int32,
    data: pointer) {.inline.} =
  ## init a Msg.
  ## TODO: Allow dataSize other than zero
  msg.next = next
  msg.rspq = rspq
  msg.cmd = cmdVal

proc newMsg(next: MsgPtr, rspq: QueuePtr, cmdVal: int32, dataSize: int):
      MsgPtr =
  ## Allocate a new Msg.
  ## TODO: Allow dataSize other than zero
  result = allocObject[Msg]()
  result.initMsg(next, rspq, cmdVal, nil)

proc delMsg(msg: MsgPtr) =
  ## Deallocate a Msg
  ## TODO: handle data size
  deallocShared(msg)

proc newMsgArena*(): MsgArenaPtr =
  when DBG: echo "newMsgArena:+"
  result = allocObject[MsgArena]()
  result.msgStack = newMpmcStack("msgStack")
  when DBG: echo "newMsgArena:-"

proc delMsgArena*(ma: MsgArenaPtr) =
  when DBG: echo "delMsgArena:+"
  block:
    while true:
      var msg = ma.msgStack.pop()
      if msg == nil:
        break;
      delMsg(msg)

    ma.msgStack.delMpmcStack()
  deallocShared(ma)
  when DBG: echo "delMsgArena:-"

proc getMsg*(ma: MsgArenaPtr, next: MsgPtr, rspq: QueuePtr, cmd: int32,
    dataSize: int): MsgPtr =
  ## Get a message from the arena or if none allocate one
  ## TODO: Allow datasize other than zero
  result = ma.msgStack.pop()
  if result == nil:
    result = newMsg(next, rspq, cmd, dataSize)
  else:
    result.initMsg(next, rspq, cmd, nil)

proc getMsg*(ma: MsgArenaPtr, rspq: QueuePtr, cmd: int32,
    dataSize: int): MsgPtr {.inline.} =
  ## Get a message from the arena or if none allocate one
  ## TODO: Allow datasize other than zero
  result = getMsg(ma, nil, rspq, cmd, dataSize)

proc getMsg*(ma: MsgArenaPtr, rspq: QueuePtr,
    cmd: int32): MsgPtr {.inline.} =
  ## Get a message from the arena or if none allocate one
  ## TODO: Allow datasize other than zero
  result = getMsg(ma, nil, rspq, cmd, 0)

proc getMsg*(ma: MsgArenaPtr, cmd: int32): MsgPtr {.inline.} =
  ## Get a message from the arena or if none allocate one
  ## TODO: Allow datasize other than zero
  result = getMsg(ma, nil, nil, cmd, 0)

proc retMsg*(ma: MsgArenaPtr, msg: MsgPtr) =
  ## Return a message to the arena
  ma.msgStack.push(msg)
