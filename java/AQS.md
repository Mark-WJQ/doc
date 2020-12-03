  
&emsp;&emsp;AbstractQueuedSynchronizer 简称 AQS，AQS普遍用于java中的并发同步控制核心是CLH队列，通过属性state来标识同步状态，
状态的变化与CLH队列的变化通过CAS来控制，底层通过调用sun.misc.Unsafe的park(),unpark()来控制线程的挂起与恢复。

&emsp;&emsp;在AQS中state可以认为是资源，一个线程想要占有资源，首先向检查state，如果state可以被占用（acquire，具体看具体场景）,则该线程可
占用相应的资源（并且通过CAS更新state,如果是独占还要将当前线程设置），占用成功后便可继续执行业务，如果资源不足或已经被占用,则将该线
程封装为一个节点并入队addWaiter，同时该线程进入自旋，检查他的前一个节点是否是head并在此尝试获取资源，如果不成功则检查该节点是否满
足挂起条件（主要是检查Node.waitStatus），如果满足将该节点挂起，等待队列前面节点执行release时唤醒，唤醒以后则继续自旋，如果获取资
源成功，则将自身节点setHead，在自旋的过程中要检查线程是否被interrupet。如果是共享锁则在acquireShared执行成功后还要看一下下一个节
点时候是共享节点，如果是则需要传递唤醒setHeadAndPropagate。同时releaseShared也会唤醒后续的节点继续执行，如果有的话。


1. 两种模式
    1.  共享(shared)
    ```java
      /**
         * Acquires in shared mode, ignoring interrupts.  Implemented by
         * first invoking at least once {@link #tryAcquireShared},
         * returning on success.  Otherwise the thread is queued, possibly
         * repeatedly blocking and unblocking, invoking {@link
         * #tryAcquireShared} until success.
         *
         * @param arg the acquire argument.  This value is conveyed to
         *        {@link #tryAcquireShared} but is otherwise uninterpreted
         *        and can represent anything you like.
         */
        public final void acquireShared(int arg) {
        // tryAcquireShared  返回值 >= 0 获取成功，直接执行，< 0 继续执行获取权限的操作
            if (tryAcquireShared(arg) < 0)
                doAcquireShared(arg);
        }
        /**
         * Acquires in shared uninterruptible mode.
         * @param arg the acquire argument
         */
        private void doAcquireShared(int arg) {
            //新增节点并入队
            final Node node = addWaiter(Node.SHARED);
            boolean failed = true;
            try {
                boolean interrupted = false;
                //自旋执行
                for (;;) {
                    final Node p = node.predecessor();
                    //前面节点是首节点，此时该节点中的线程被唤醒，开始执行
                    if (p == head) {
                        //再次尝试获取权限，try方法每个具体实现类的策略都不同，需要具体分析
                        int r = tryAcquireShared(arg);
                        if (r >= 0) {
                            //设置手节点并先后传递
                            setHeadAndPropagate(node, r);
                            //释放节点
                            p.next = null; // help GC
                            if (interrupted)
                                selfInterrupt();
                            failed = false;
                            return;
                        }
                    }
                    //根据waitStatus确定是否需要挂起线程，挂起线程并检查该线程会否被中断
                    if (shouldParkAfterFailedAcquire(p, node) &&
                        parkAndCheckInterrupt())
                        interrupted = true;
                }
            } finally {
                if (failed)
                //基本上是节点线程被interrupt,顺便唤醒下个节点执行
                    cancelAcquire(node);
            }
        }


    //-----------------------释放共享-------------------------------------

        /**
         * Releases in shared mode.  Implemented by unblocking one or more
         * threads if {@link #tryReleaseShared} returns true.
         *
         * @param arg the release argument.  This value is conveyed to
         *        {@link #tryReleaseShared} but is otherwise uninterpreted
         *        and can represent anything you like.
         * @return the value returned from {@link #tryReleaseShared}
         */
        public final boolean releaseShared(int arg) {
            //try方法尝试释放资源，通过检查操作state，在实现类中实际逻辑不同
            if (tryReleaseShared(arg)) {
                doReleaseShared();
                return true;
            }
            return false;
        }


         /**
         * Release action for shared mode -- signals successor and ensures
         * propagation. (Note: For exclusive mode, release just amounts
         * to calling unparkSuccessor of head if it needs signal.)
         */
        private void doReleaseShared() {
            /*
             * 自旋
             * Ensure that a release propagates, even if there are other
             * in-progress acquires/releases.  This proceeds in the usual
             * way of trying to unparkSuccessor of head if it needs
             * signal. But if it does not, status is set to PROPAGATE to
             * ensure that upon release, propagation continues.
             * Additionally, we must loop in case a new node is added
             * while we are doing this. Also, unlike other uses of
             * unparkSuccessor, we need to know if CAS to reset status
             * fails, if so rechecking.
             */
            for (;;) {
                Node h = head;
                if (h != null && h != tail) {
                    int ws = h.waitStatus;
                    //需要通知下一个节点
                    if (ws == Node.SIGNAL) {
                        // cas 替换状态，如果成功说明其他线程没有操作，则通知下一个节点
                        if (!compareAndSetWaitStatus(h, Node.SIGNAL, 0))
                            continue;            // loop to recheck cases
                       //唤醒下一个节点
                        unparkSuccessor(h);
                    }
                    else if (ws == 0 &&
                             !compareAndSetWaitStatus(h, 0, Node.PROPAGATE))
                        continue;                // loop on failed CAS
                }
                //如果头结点没变基本说明后面没有节点或后续节点不满足被唤醒的条件
                // ，因为后续节点被唤醒后的第一件事就是将头结点变成当前节点，这样该线程可以帮忙唤醒更多的节点
                if (h == head)                   // loop if head changed
                    break;
            }
        }
    ```
   2. 涉及类
    ```java
    Semaphore

     // state 在此处是信号量，在初始化时就指定并发量，
    //在每次尝试长有资源时，减去要占用的资源数量，直到可用资源数为0
     final int nonfairTryAcquireShared(int acquires) {
                for (;;) {
                    int available = getState();
                    int remaining = available - acquires;
                    if (remaining < 0 || compareAndSetState(available, remaining))
                        return remaining;
                }
        }

      // 释放信号量，将被占用的信号量放回去  
      protected final boolean tryReleaseShared(int releases) {
          for (;;) {
              int current = getState();
              int next = current + releases;
              if (next < current) // overflow
                  throw new Error("Maximum permit count exceeded");
              if (compareAndSetState(current, next))
                  return true;
          }
       }

    //-------------------------------------------------------------------------
    CountDownLatch

    protected int tryAcquireShared(int acquires) {
        return (getState() == 0) ? 1 : -1;
    }
    ​
    ​
    protected boolean tryReleaseShared(int releases) {
        // Decrement count; signal when transition to zero
        for (;;) {
            int c = getState();
            if (c == 0)
                return false;
            int nextc = c-1;
            if (compareAndSetState(c, nextc))
                return nextc == 0;
        }
    }
    ```
    3. 独占(exclusive)
    ```java
    /**
         * Acquires in exclusive mode, ignoring interrupts.  Implemented
         * by invoking at least once {@link #tryAcquire},
         * returning on success.  Otherwise the thread is queued, possibly
         * repeatedly blocking and unblocking, invoking {@link
         * #tryAcquire} until success.  This method can be used
         * to implement method {@link Lock#lock}.
         *
         * @param arg the acquire argument.  This value is conveyed to
         *        {@link #tryAcquire} but is otherwise uninterpreted and
         *        can represent anything you like.
         */
        public final void acquire(int arg) {
             //尝试占用资源，不成功的话入队独占模式并自旋  
            if (!tryAcquire(arg) &&
                acquireQueued(addWaiter(Node.EXCLUSIVE), arg))
                // 是否需要中断执行            
                selfInterrupt();
        }

          /**
         * Acquires in exclusive uninterruptible mode for thread already in
         * queue. Used by condition wait methods as well as acquire.
         *
         * @param node the node
         * @param arg the acquire argument
         * @return {@code true} if interrupted while waiting
         */
        final boolean acquireQueued(final Node node, int arg) {
            boolean failed = true;
            try {
                boolean interrupted = false;
                //自旋操作
                for (;;) {
                    final Node p = node.predecessor();
                    // 检查前节点是否为头结点并尝试占用资源
                    if (p == head && tryAcquire(arg)) {
                        // 成功设置头结点
                        setHead(node);
                        p.next = null; // help GC
                        failed = false;
                        return interrupted;
                    }
                    //检查是否满足获取失败后挂起线程，主要是检查Node.waitStatus
                    //满足挂起条件的话挂起线程并在该线程被唤醒后检查该线程是否被interrupt
                    if (shouldParkAfterFailedAcquire(p, node) &&
                        parkAndCheckInterrupt())
                        interrupted = true;
                }
            } finally {
                if (failed)
                    cancelAcquire(node);
            }
        }

          /**
         * 首先检查前置节点的 waitStatus 如果状态是 SIGNAL 说明前置节点还在等待中，如果他执行完会唤醒下一个节点
         * 如果状态 > 0 ,应为目前只有取消状态大于0（ CANCELLED =  1），说明前置节点已经取消，此时我们要找到前面最后一个没有被取消的节点，并关联
         * 如果是其他状态的话，则将前置状态的节点设为 SIGNAL，让它在执行完后记得通知我，我就先挂为敬了
         *
         * Checks and updates status for a node that failed to acquire.
         * Returns true if thread should block. This is the main signal
         * control in all acquire loops.  Requires that pred == node.prev.
         *
         * @param pred node's predecessor holding status
         * @param node the node
         * @return {@code true} if thread should block
         */
        private static boolean shouldParkAfterFailedAcquire(Node pred, Node node) {
            int ws = pred.waitStatus;
            if (ws == Node.SIGNAL)
                /*
                 * This node has already set status asking a release
                 * to signal it, so it can safely park.
                 */
                return true;
            if (ws > 0) {
                /*
                 * Predecessor was cancelled. Skip over predecessors and
                 * indicate retry.
                 */
                do {
                    node.prev = pred = pred.prev;
                } while (pred.waitStatus > 0);
                pred.next = node;
            } else {
                /*
                 * waitStatus must be 0 or PROPAGATE.  Indicate that we
                 * need a signal, but don't park yet.  Caller will need to
                 * retry to make sure it cannot acquire before parking.
                 */
                compareAndSetWaitStatus(pred, ws, Node.SIGNAL);
            }
            return false;
        }

     /**
       * 独占模式下释放资源
       *  
         * Releases in exclusive mode.  Implemented by unblocking one or
         * more threads if {@link #tryRelease} returns true.
         * This method can be used to implement method {@link Lock#unlock}.
         *
         * @param arg the release argument.  This value is conveyed to
         *        {@link #tryRelease} but is otherwise uninterpreted and
         *        can represent anything you like.
         * @return the value returned from {@link #tryRelease}
         */
        public final boolean release(int arg) {
            // 尝试释放资源不同实现类的策略不同
            if (tryRelease(arg)) {
                Node h = head;
                // h.waitStatus 在执行 unparkSuccessor 时会将状态置为 0
                if (h != null && h.waitStatus != 0)
                    // h唤醒后续节点
                    unparkSuccessor(h);
                return true;
            }
            return false;
        }

        /**
         * Wakes up node's successor, if one exists.
         *
         * @param node the node
         */
        private void unparkSuccessor(Node node) {
            /*
             * If status is negative (i.e., possibly needing signal) try
             * to clear in anticipation of signalling.  It is OK if this
             * fails or if status is changed by waiting thread.
             */
            int ws = node.waitStatus;
            if (ws < 0)
                compareAndSetWaitStatus(node, ws, 0);
    ​
            /*
             * Thread to unpark is held in successor, which is normally
             * just the next node.  But if cancelled or apparently null,
             * traverse backwards from tail to find the actual
             * non-cancelled successor.
             */
            Node s = node.next;
            if (s == null || s.waitStatus > 0) {
                s = null;
                for (Node t = tail; t != null && t != node; t = t.prev)
                    if (t.waitStatus <= 0)
                        s = t;
            }
            if (s != null)
                LockSupport.unpark(s.thread);
        }
    ```
    4. 涉及类
        1. ReentrantLock可重入，公平/非公平，定时，notify
        ```java


         /** 非公平锁尝试获取，非公平锁在获取资源的不会去检查队列中是否有等待线程，如果发现state可以占用
          * 会直接尝试占用，占用成功便直接执行这样也会减少线程状态切换带来的损耗，相对来说非公平锁的效率较高 
           * Performs non-fair tryLock.  tryAcquire is implemented in
           * subclasses, but both need nonfair try for trylock method.
           */
          final boolean nonfairTryAcquire(int acquires) {
              final Thread current = Thread.currentThread();
              int c = getState();
              if (c == 0) {
                  if (compareAndSetState(0, acquires)) {
                      setExclusiveOwnerThread(current);
                      return true;
                  }
              }
              else if (current == getExclusiveOwnerThread()) {
                  int nextc = c + acquires;
                  if (nextc < 0) // overflow
                      throw new Error("Maximum lock count exceeded");
                  setState(nextc);
                  return true;
              }
              return false;
          }
         //公平锁尝试占用资源
         protected final boolean tryAcquire(int acquires) {
              final Thread current = Thread.currentThread();
              int c = getState();

              if (c == 0) {
                  //当前无锁，判断队列中是否有等待节点，如果没有cas更新资源状态，设置独占线程      
                  if (!hasQueuedPredecessors() &&
                      compareAndSetState(0, acquires)) {
                      setExclusiveOwnerThread(current);
                      return true;
                  }
              }
              else if (current == getExclusiveOwnerThread()) {
                  //同一个线程重入，当然可以进来          
                  int nextc = c + acquires;
                  if (nextc < 0)
                      throw new Error("Maximum lock count exceeded");
                  setState(nextc);
                  return true;
              }
              return false;
          }

        ​
         // 可重入锁尝试释放资源 
         protected final boolean tryRelease(int releases) {
              int c = getState() - releases;
              //判断是否为同一个线程      
              if (Thread.currentThread() != getExclusiveOwnerThread())
                  throw new IllegalMonitorStateException();
              boolean free = false;
              if (c == 0) {
                  free = true;
                  setExclusiveOwnerThread(null);
              }
              //cas 更新状态      
              setState(c);
              return free;
           }
        java.util.concurrent.ThreadPoolExecutor.Worker
        ```
        2. CyclicBarrier
        CycliBarrier 的同步实现是通过ReentrantLockde,Condition实现的，主要是condition.await(),singlAll(),来实现它的功能目的，即parties个线程在互相等待都到达触发点后触发。

        3. Condition
        Condition 是实现条件锁，通过与ReenttrantLock配合，将需要挂起的线程新封装一个Node节点（Node.CONDITION）加入condition队列，然后释放锁资源，将当前线程挂起,在被重新唤醒后再次获取lock锁（acquireQueued）,并且清除后面取消的节点。唤醒操作，在条件合适的时候调用signal或signalAll，将被唤醒的节点一般是firstWaiter节点（未被取消），加入lock队列，如果signalAll的话会遍历所有waiter节点，并加入lock队列
        ```java

        /** 
         * Implements interruptible condition wait.
         * <ol>
         * <li> If current thread is interrupted, throw InterruptedException.
         * <li> Save lock state returned by {@link #getState}.
         * <li> Invoke {@link #release} with saved state as argument,
         *      throwing IllegalMonitorStateException if it fails.
         * <li> Block until signalled or interrupted.
         * <li> Reacquire by invoking specialized version of
         *      {@link #acquire} with saved state as argument.
         * <li> If interrupted while blocked in step 4, throw InterruptedException.
         * </ol>
         */
        public final void await() throws InterruptedException {
            if (Thread.interrupted())
                throw new InterruptedException();
            // 加入waiter队列        
            Node node = addConditionWaiter();
          // 释放lock，并唤醒后面的节点   
            int savedState = fullyRelease(node);
            int interruptMode = 0;
            // 检查一下节点会否在lock队列中，应该是怕执行singl    
            while (!isOnSyncQueue(node)) {
                //挂起    
                LockSupport.park(this);
                if ((interruptMode = checkInterruptWhileWaiting(node)) != 0)
                    break;
            }
            // 被唤醒后的操作，重新在Lock队列中获取资源占用锁  
            if (acquireQueued(node, savedState) && interruptMode != THROW_IE)
                interruptMode = REINTERRUPT;
            if (node.nextWaiter != null) // clean up if cancelled
                unlinkCancelledWaiters();
            if (interruptMode != 0)
                reportInterruptAfterWait(interruptMode);
        }
        ​
         private void doSignal(Node first) {
              do {
                  if ( (firstWaiter = first.nextWaiter) == null)
                      lastWaiter = null;
                  first.nextWaiter = null;
              } while (!transferForSignal(first) &&
                       (first = firstWaiter) != null);
          }
        ​
          /**
         * Transfers a node from a condition queue onto sync queue.
         * Returns true if successful.
         * @param node the node
         * @return true if successfully transferred (else the node was
         * cancelled before signal)
         */
        final boolean transferForSignal(Node node) {
            /*
              * 如果waitStatus 不是Condition的话只能是被取消了    
             * If cannot change waitStatus, the node has been cancelled.
             */
            if (!compareAndSetWaitStatus(node, Node.CONDITION, 0))
                return false;
        ​
            /*
             * 在在被唤醒后首先加入lock队尾    
             * Splice onto queue and try to set waitStatus of predecessor to
             * indicate that thread is (probably) waiting. If cancelled or
             * attempt to set waitStatus fails, wake up to resync (in which
             * case the waitStatus can be transiently and harmlessly wrong).
             */
            Node p = enq(node);
            int ws = p.waitStatus;
            if (ws > 0 || !compareAndSetWaitStatus(p, ws, Node.SIGNAL))
                LockSupport.unpark(node.thread);
            return true;
        }
        ```
    
    5. 读写锁
    ReentrantReadWriteLock, Aqs中的state，低16位表示写锁，高位表示读锁
    6. 属性
    Node -> 同步节点，waitStatus 该节点状态，标识下一步可执行状态 
    ```java
    /**
    * Wait queue node class.
    *
    * <p>The wait queue is a variant of a "CLH" (Craig, Landin, and
    * Hagersten) lock queue. CLH locks are normally used for
    * spinlocks.  We instead use them for blocking synchronizers, but
    * use the same basic tactic of holding some of the control
    * information about a thread in the predecessor of its node.  A
    * "status" field in each node keeps track of whether a thread
    * should block.  A node is signalled when its predecessor
    * releases.  Each node of the queue otherwise serves as a
    * specific-notification-style monitor holding a single waiting
    * thread. The status field does NOT control whether threads are
    * granted locks etc though.  A thread may try to acquire if it is
    * first in the queue. But being first does not guarantee success;
    * it only gives the right to contend.  So the currently released
    * contender thread may need to rewait.
    *
    * <p>To enqueue into a CLH lock, you atomically splice it in as new
    * tail. To dequeue, you just set the head field.
    * <pre>
    *      +------+  prev +-----+       +-----+
    * head |      | <---- |     | <---- |     |  tail
    *      +------+       +-----+       +-----+
    * </pre>
    *
    * <p>Insertion into a CLH queue requires only a single atomic
    * operation on "tail", so there is a simple atomic point of
    * demarcation from unqueued to queued. Similarly, dequeuing
    * involves only updating the "head". However, it takes a bit
    * more work for nodes to determine who their successors are,
    * in part to deal with possible cancellation due to timeouts
    * and interrupts.
    *
    * <p>The "prev" links (not used in original CLH locks), are mainly
    * needed to handle cancellation. If a node is cancelled, its
    * successor is (normally) relinked to a non-cancelled
    * predecessor. For explanation of similar mechanics in the case
    * of spin locks, see the papers by Scott and Scherer at
    * http://www.cs.rochester.edu/u/scott/synchronization/
    *
    * <p>We also use "next" links to implement blocking mechanics.
    * The thread id for each node is kept in its own node, so a
    * predecessor signals the next node to wake up by traversing
    * next link to determine which thread it is.  Determination of
    * successor must avoid races with newly queued nodes to set
    * the "next" fields of their predecessors.  This is solved
    * when necessary by checking backwards from the atomically
    * updated "tail" when a node's successor appears to be null.
    * (Or, said differently, the next-links are an optimization
    * so that we don't usually need a backward scan.)
    *
    * <p>Cancellation introduces some conservatism to the basic
    * algorithms.  Since we must poll for cancellation of other
    * nodes, we can miss noticing whether a cancelled node is
    * ahead or behind us. This is dealt with by always unparking
    * successors upon cancellation, allowing them to stabilize on
    * a new predecessor, unless we can identify an uncancelled
    * predecessor who will carry this responsibility.
    *
    * <p>CLH queues need a dummy header node to get started. But
    * we don't create them on construction, because it would be wasted
    * effort if there is never contention. Instead, the node
    * is constructed and head and tail pointers are set upon first
    * contention.
    *
    * <p>Threads waiting on Conditions use the same nodes, but
    * use an additional link. Conditions only need to link nodes
    * in simple (non-concurrent) linked queues because they are
    * only accessed when exclusively held.  Upon await, a node is
    * inserted into a condition queue.  Upon signal, the node is
    * transferred to the main queue.  A special value of status
    * field is used to mark which queue a node is on.
    *
    * <p>Thanks go to Dave Dice, Mark Moir, Victor Luchangco, Bill
    * Scherer and Michael Scott, along with members of JSR-166
    * expert group, for helpful ideas, discussions, and critiques
    * on the design of this class.
    */
    static final class Node {
     /** Marker to indicate a node is waiting in shared mode */
     static final Node SHARED = new Node();
     /** Marker to indicate a node is waiting in exclusive mode */
     static final Node EXCLUSIVE = null;
    ​
     /** waitStatus value to indicate thread has cancelled */
     static final int CANCELLED =  1;
     /** waitStatus value to indicate successor's thread needs unparking */
     static final int SIGNAL    = -1;
     /** waitStatus value to indicate thread is waiting on condition */
     static final int CONDITION = -2;
     /**
      * waitStatus value to indicate the next acquireShared should
      * unconditionally propagate
      */
     static final int PROPAGATE = -3;
    ​
     /**
      * Status field, taking on only the values:
      *   SIGNAL:     The successor of this node is (or will soon be)
      *               blocked (via park), so the current node must
      *               unpark its successor when it releases or
      *               cancels. To avoid races, acquire methods must
      *               first indicate they need a signal,
      *               then retry the atomic acquire, and then,
      *               on failure, block.
      *   CANCELLED:  This node is cancelled due to timeout or interrupt.
      *               Nodes never leave this state. In particular,
      *               a thread with cancelled node never again blocks.
      *   CONDITION:  This node is currently on a condition queue.
      *               It will not be used as a sync queue node
      *               until transferred, at which time the status
      *               will be set to 0. (Use of this value here has
      *               nothing to do with the other uses of the
      *               field, but simplifies mechanics.)
      *   PROPAGATE:  A releaseShared should be propagated to other
      *               nodes. This is set (for head node only) in
      *               doReleaseShared to ensure propagation
      *               continues, even if other operations have
      *               since intervened.
      *   0:          None of the above
      *
      * The values are arranged numerically to simplify use.
      * Non-negative values mean that a node doesn't need to
      * signal. So, most code doesn't need to check for particular
      * values, just for sign.
      *
      * The field is initialized to 0 for normal sync nodes, and
      * CONDITION for condition nodes.  It is modified using CAS
      * (or when possible, unconditional volatile writes).
      */
     volatile int waitStatus;
    ​
     /**
      * Link to predecessor node that current node/thread relies on
      * for checking waitStatus. Assigned during enqueuing, and nulled
      * out (for sake of GC) only upon dequeuing.  Also, upon
      * cancellation of a predecessor, we short-circuit while
      * finding a non-cancelled one, which will always exist
      * because the head node is never cancelled: A node becomes
      * head only as a result of successful acquire. A
      * cancelled thread never succeeds in acquiring, and a thread only
      * cancels itself, not any other node.
      */
     volatile Node prev;
    ​
     /**
      * Link to the successor node that the current node/thread
      * unparks upon release. Assigned during enqueuing, adjusted
      * when bypassing cancelled predecessors, and nulled out (for
      * sake of GC) when dequeued.  The enq operation does not
      * assign next field of a predecessor until after attachment,
      * so seeing a null next field does not necessarily mean that
      * node is at end of queue. However, if a next field appears
      * to be null, we can scan prev's from the tail to
      * double-check.  The next field of cancelled nodes is set to
      * point to the node itself instead of null, to make life
      * easier for isOnSyncQueue.
      */
     volatile Node next;
    ​
     /**
      * The thread that enqueued this node.  Initialized on
      * construction and nulled out after use.
      */
     volatile Thread thread;
    ​
     /**
      * Link to next node waiting on condition, or the special
      * value SHARED.  Because condition queues are accessed only
      * when holding in exclusive mode, we just need a simple
      * linked queue to hold nodes while they are waiting on
      * conditions. They are then transferred to the queue to
      * re-acquire. And because conditions can only be exclusive,
      * we save a field by using special value to indicate shared
      * mode.
      */
     Node nextWaiter;
    ​
     /**
      * Returns true if node is waiting in shared mode.
      */
     final boolean isShared() {
         return nextWaiter == SHARED;
     }
    ​
     /**
      * Returns previous node, or throws NullPointerException if null.
      * Use when predecessor cannot be null.  The null check could
      * be elided, but is present to help the VM.
      *
      * @return the predecessor of this node
      */
     final Node predecessor() throws NullPointerException {
         Node p = prev;
         if (p == null)
             throw new NullPointerException();
         else
             return p;
     }

    }
    ```



