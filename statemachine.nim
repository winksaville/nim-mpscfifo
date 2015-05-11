## A state machine where the current state is defined as
## a process to exeucte. This will evolve into a hierarchical
## state machine with enter and exit methods and problably
## using templates or macros to make it easy to use.
import msg, msgarena, msglooper, mpscfifo, fifoutils, tables, typeinfo, os

type
  StateInfo[TypeState] = object of RootObj
    name: string
    enter: TypeState
    exit: TypeState
    state: TypeState
    parentStateInfo: ref StateInfo[TypeState]

  StateMachine*[TypeState] = object of Component
    protocols*: seq[int]
    curState*: TypeState
    stateStack: seq[ref StateInfo[TypeState]]
    tempStack: seq[ref StateInfo[TypeState]]
    ma*: MsgArenaPtr
    ml*: MsgLooperPtr
    states: TableRef[TypeState, ref StateInfo[TypeState]]


proc dispatcher[TypeStateMachine](cp: ComponentPtr, msg: MsgPtr) =
  ## dispatcher cast cp to a TypeStateMachine and call current state
  var sm = cast[ref TypeStateMachine](cp)
  sm.curState(sm, msg)
  sm.performTransitions(msg)

proc newStateInfo[TypeState](sm: ref StateMachine[TypeState], name: string,
    state: TypeState, enter: TypeState, exit: TypeState, parent: TypeState):
      ref StateInfo[TypeState] =
  var
    parentStateInfo: ref StateInfo[TypeState]

  new(result)
  if parent != nil and hasKey[TypeState, ref StateInfo[TypeState]](
      sm.states, parent):
    parentStateInfo = mget[TypeState, ref StateInfo[TypeState]](
      sm.states, parent)
    echo "parent=", parentStateInfo.name
  else:
    echo "parent not in table"
    parentStateInfo = nil
  result.name = name
  result.enter = enter
  result.exit = exit
  result.state = state
  result.parentStateInfo = parentStateInfo

proc initStateMachine*[TypeStateMachine, TypeState](
    sm: ref StateMachine[TypeState], name: string, ml: MsgLooperPtr) =
  ## Initialize StateMachine
  echo "initStateMacineX: e"
  sm.states = newTable[TypeState, ref StateInfo[TypeState]]()
  sm.name = name
  sm.pm = dispatcher[TypeStateMachine]
  sm.ma = newMsgArena()
  sm.ml = ml
  sm.rcvq = newMpscFifo("fifo_" & name, sm.ma, sm.ml)
  sm.curState = nil
  sm.stateStack = @[]
  sm.tempStack = @[]
  echo "initStateMacineX: x"

proc deinitStateMachine*[TypeState](sm: ref StateMachine[TypeState]) =
  ## deinitialize StateMachine
  sm.rcvq.delMpscFifo()
  sm.ma.delMsgArena()

proc moveTempStackToStateStack[TypeStateMachine](sm: ref TypeStateMachine):
    int =
  ## Move the contents of the temporary stack to the state stack
  ## reversion the order of the items which are on the temporary
  ## stack.
  ##
  ## result is the index into sm.stateStack where entering needs to start
  result = sm.stateStack.high + 1
  for i in countdown(sm.tempStack.high, 0):
    var curSi = sm.tempStack[i]
    sm.stateStack.add(sm.tempStack[i])

proc performTransitions[TypeStateMachine](sm: ref TypeStateMachine,
    msg: MsgPtr) =
  ## TODO: Preform transitions

proc invokeEnterProcs[TypeStateMachine](sm: ref TypeStateMachine,
    stateStackEnteringIndex: int) =
  for i in countup(stateStackEnteringIndex, sm.stateStack.high):
    var enter = sm.stateStack[i].enter
    if enter != nil:
      enter(sm, nil)

proc startStateMachine*[TypeStateMachine, TypeState](sm: ref TypeStateMachine,
    initialState: TypeState) =
  ## Start the state machine at initialState
  sm.curState = initialState

  # Push onto the tempStack current and all its parents.
  var  curSi = mget[TypeState, ref StateInfo[TypeState]](
        sm.states, sm.curState)
  while curSi != nil:
    sm.tempStack.add(curSi)
    curSi = curSi.parentStateInfo

  # Start with empty stack
  sm.stateStack.setLen(0)
  invokeEnterProcs[TypeStateMachine](sm, moveTempStackToStateStack(sm))

proc addStateEXP*[TypeState](sm: ref StateMachine[TypeState], name: string,
    state: TypeState, enter: TypeState, exit: TypeState,
    parent: TypeState) =
  ## Add a new state to the hierarchy. The parent argument may be nil
  ## if the state has no parent.
  if hasKey[TypeState, ref StateInfo[TypeState]](sm.states, state):
    doAssert(false, "state already added: " & name)
  else:
    var stateInfo = newStateInfo[TypeState](sm, name, state, enter, exit, parent)
    echo "addState: state=", stateInfo.name
    var parentName: string
    if stateInfo.parentStateInfo != nil:
      parentName = stateInfo.parentStateInfo.name
    else:
      parentName = "<nil>"
    echo "addState: parent=", parentName
    add[TypeState, ref StateInfo[TypeState]](sm.states, state, stateInfo)

proc addState*[TypeState](sm: ref StateMachine[TypeState], name: string,
    state: TypeState) =
  ## Add a new state to the hierarchy. The parent argument may be nil
  ## if the state has no parent.
  addStateEXP[TypeState](sm, name, state, nil, nil, nil)

proc transitionTo*[TypeState](sm: ref StateMachine[TypeState],
    state: TypeState) =
  ## Transition to a new state
  sm.curState = state

when isMainModule:
  import unittest

  suite "t1":
    type
      SmT1State = proc(sm: ref SmT1, msg: MsgPtr)
      SmT1 = object of StateMachine[SmT1State]
        ## SmT1 is a statemachine with a counter
        count: int
        defaultCount: int
        s0Count: int
        s1Count: int

    ## Forward declare states
    proc default(sm: ref SmT1, msg: MsgPtr)
    proc s1(sm: ref SmT1, msg: MsgPtr)
    proc s0(sm: ref SmT1, msg: MsgPtr)

    proc defaultEnter(sm: ref SmT1, msg: MsgPtr) =
      echo "defaultEnter"
    proc defaultExit(sm: ref SmT1, msg: MsgPtr) =
      echo "defaultExit"
    proc default(sm: ref SmT1, msg: MsgPtr) =
      ## default state no transition increments counters
      sm.count += 1
      sm.defaultCount += 1
      echo "default: count=", sm.count
      msg.rspq.add(msg)

    proc s0Enter(sm: ref SmT1, msg: MsgPtr) =
      echo "s0Enter"
    proc s0Exit(sm: ref SmT1, msg: MsgPtr) =
      echo "s0Exit"
    proc s0(sm: ref SmT1, msg: MsgPtr) =
      ## S0 state transitions to S1 increments counter
      sm.count += 1
      sm.s0Count += 1
      echo "s0: count=", sm.count
      transitionTo[SmT1State](sm, s1)
      msg.rspq.add(msg)

    proc s1Enter(sm: ref SmT1, msg: MsgPtr) =
      echo "s1Enter"
    proc s1Exit(sm: ref SmT1, msg: MsgPtr) =
      echo "s1Exit"
    proc s1(sm: ref SmT1, msg: MsgPtr) =
      ## S1 state transitions to S0 and increments counter
      sm.count += 1
      sm.s1Count += 1
      echo "s1: count=", sm.count
      transitionTo[SmT1State](sm, s0)
      msg.rspq.add(msg)

    proc newSmT1NonState(ml: MsgLooperPtr): ref SmT1 =
      echo "initSmT1NonState:+"
      ## Create a new SmT1 state machine
      new(result)
      initStateMachine[SmT1, SmT1State](result, "smt1", ml)
      result.count = 0
      result.defaultCount = 0
      result.s0Count = 0
      result.s1Count = 0

    proc newSmT1OneState(ml: MsgLooperPtr): ptr Component =
      var smT1 = newSmT1NonState(ml)

      addState[SmT1State](smT1, "default", default)
      startStateMachine[SmT1, SmT1State](smT1, default)
      # TODO: DANGEROUS, but addComponent requires this to return a ptr
      result = cast[ptr Component](smT1)
      echo "newSmT1OneState:-"

    proc newSmT1TwoStates(ml: MsgLooperPtr): ptr Component =
      var smT1 = newSmT1NonState(ml)

      addState[SmT1State](smT1, "s0", s0)
      addState[SmT1State](smT1, "s1", s1)
      startStateMachine[SmT1, SmT1State](smT1, s0)
      # TODO: DANGEROUS, but addComponent requires this to return a ptr
      result = cast[ptr Component](smT1)
      echo "newSmT1TwoStates:-"

    proc newSmT1TriangleStates(ml: MsgLooperPtr): ptr Component =
      var smT1 = newSmT1NonState(ml)

      addStateEXP[SmT1State](smT1, "default", default, defaultEnter, defaultExit, nil)
      addStateEXP[SmT1State](smT1, "s0", s0, s0Enter, s0Exit, default)
      addStateEXP[SmT1State](smT1, "s1", s1, s1Enter, s1Exit, default)
      startStateMachine[SmT1, SmT1State](smT1, s0)
      # TODO: DANGEROUS, but addComponent requires this to return a ptr
      result = cast[ptr Component](smT1)
      echo "newSmT1TringleStates:-"

    proc delSmT1(cp: ptr Component) =
      echo "delSmT1:+"
      deinitStateMachine[SmT1State](cast[ref SmT1](cp))
      echo "delSmT1:-"

    var
      smT1: ptr SmT1
      msg: MsgPtr
      ma = newMsgArena()
      rcvq = newMpscFifo("rcvq", ma)
      ml = newMsgLooper("ml_smt1")

    test "test-add-del-component":
      echo "test-add-del-component"

      proc checkSendingTwoMsgs(sm: ptr SmT1, ma: MsgArenaPtr,
          rcvq: MsgQueuePtr) =
        # Send first message, should be processed by default
        var msg: MsgPtr
        msg = ma.getMsg(rcvq, 1)
        sm.rcvq.add(msg)
        msg = rcvq.rmv()
        check msg.cmd == 1
        check sm.count == 1
        check sm.defaultCount == 1
        check sm.s0Count == 0
        check sm.s1Count == 0

        # Send second message, should be processed by default
        msg = ma.getMsg(rcvq, 2)
        sm.rcvq.add(msg)
        msg = rcvq.rmv()
        check msg.cmd == 2
        check sm.count == 2
        check sm.defaultCount == 2
        check sm.s0Count == 0
        check sm.s1Count == 0

      var sm1 = addComponent[SmT1](ml, newSmT1OneState)
      checkSendingTwoMsgs(sm1, ma, rcvq)

      var sm2 = addComponent[SmT1](ml, newSmT1OneState)
      checkSendingTwoMsgs(sm2, ma, rcvq)

      # delete the first one added
      delComponent(ml, sm1, delSmT1)
      # delete it again, be sure nothing blows up
      delComponent(ml, sm1, delSmT1)

      ## Add first one back, this will use the first slot
      sm1 = addComponent[SmT1](ml, newSmT1OneState)
      checkSendingTwoMsgs(sm1, ma, rcvq)

      ## delete both
      delComponent(ml, sm1, delSmT1)
      delComponent(ml, sm2, delSmT1)

    # Tests default as the one and only state
    setup:
      smT1 = addComponent[SmT1](ml, newSmT1OneState)

    teardown:
      delComponent(ml, smT1, delSmT1)
      smT1 = nil

    test "test-one-state":
      echo "test-one-state"

      proc checkSendingTwoMsgs(sm: ptr SmT1, ma: MsgArenaPtr,
          rcvq: MsgQueuePtr) =
        # Send first message, should be processed by default
        var msg: MsgPtr
        msg = ma.getMsg(rcvq, 1)
        sm.rcvq.add(msg)
        msg = rcvq.rmv()
        check msg.cmd == 1
        check sm.count == 1
        check sm.defaultCount == 1
        check sm.s0Count == 0
        check sm.s1Count == 0

        # Send second message, should be processed by default
        msg = ma.getMsg(rcvq, 2)
        sm.rcvq.add(msg)
        msg = rcvq.rmv()
        check msg.cmd == 2
        check sm.count == 2
        check sm.defaultCount == 2
        check sm.s0Count == 0
        check sm.s1Count == 0

      check smT1.stateStack.low == 0
      check smT1.stateStack.high == 0
      check smT1.stateStack[0].name == "default"
      checkSendingTwoMsgs(smT1, ma, rcvq)

    # Test with two states s0, s1
    setup:
      smT1 = addComponent[SmT1](ml, newSmT1TwoStates)

    teardown:
      delComponent(ml, smT1, delSmT1)
      smT1 = nil

    test "test-two-states":
      var
        rcvq = newMpscFifo("rcvq", smT1.ma)
        msg: MsgPtr

      check smT1.stateStack.low == 0
      check smT1.stateStack.high == 0
      check smT1.stateStack[0].name == "s0"

      # Send first message, should be processed by S0
      msg = smT1.ma.getMsg(rcvq, 1)
      smT1.rcvq.add(msg)
      msg = rcvq.rmv()
      check msg.cmd == 1
      check smt1.count == 1
      check smt1.defaultCount == 0
      check smt1.s0Count == 1
      check smt1.s1Count == 0

      # Send second message, should be processed by S1
      msg = smT1.ma.getMsg(rcvq, 2)
      smT1.rcvq.add(msg)
      msg = rcvq.rmv()
      check msg.cmd == 2
      check smt1.count == 2
      check smt1.defaultCount == 0
      check smt1.s0Count == 1
      check smt1.s1Count == 1

    # Test with default and two child states s0, s1 in a triangle
    # TODO: Add passing of unhandled message and verify
    # TODO: that default is invoked
    setup:
      smT1 = addComponent[SmT1](ml, newSmT1TriangleStates)

    teardown:
      delComponent(ml, smT1, delSmT1)
      smT1 = nil

    test "test-trinagle-states":
      var
        rcvq = newMpscFifo("rcvq", smT1.ma)
        msg: MsgPtr

      check smT1.stateStack.low == 0
      check smT1.stateStack.high == 1
      check smT1.stateStack[0].name == "default"
      check smT1.stateStack[1].name == "s0"

      # Send first message, should be processed by S0
      msg = smT1.ma.getMsg(rcvq, 1)
      smT1.rcvq.add(msg)
      msg = rcvq.rmv()
      check msg.cmd == 1
      check smt1.count == 1
      check smt1.defaultCount == 0
      check smt1.s0Count == 1
      check smt1.s1Count == 0

      # Send second message, should be processed by S1
      msg = smT1.ma.getMsg(rcvq, 2)
      smT1.rcvq.add(msg)
      msg = rcvq.rmv()
      check msg.cmd == 2
      check smt1.count == 2
      check smt1.defaultCount == 0
      check smt1.s0Count == 1
      check smt1.s1Count == 1
