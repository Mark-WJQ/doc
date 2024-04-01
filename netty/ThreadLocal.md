1. 定义
    * 在Thread中添加一个副本，该副本只存储与该Thread相关的内容，副本的修改与获取只能通过当前线程操作
2. ThreadLocal的目的
   1. 解决线程间数据冲突，在线程间隔离变量
3. 实现方式
   * Thread 中维护了一个ThreadLocalMap 对象，key为 ThreadLocal对象，value 为副本
   * 在ThreadLocal 中的所有操作，都会先找到当前线程，在线程中找到Map
   * ThreadLocalMap的操作是指针探测方式实现的，如果hash冲突严重，且数据量大的话，操作代价较高
   * ThreadLocalMap.Entry extends WeakReference, 弱引用在发生GC的时候便会被回收，弱引用指向key，所以会出现key=null，value有值的情况，操作get/set 的时候会主动检测key=null的情况，并清除释放
4. 注意事项
   1. 使用完成后要主动remove，避免内存泄露
   2. 线程池复用时候需要注意清理
   3. 父子线程间的传递

###### netty FastThreadLocal
1. 成员
   * FastThreadLocal
   * FastThreadLocalThread
   * FastThreadLocalMap
2. 实现方式
   * 与原生主要区别是，FastThreadLocalMap 实现方式是直接使用下标索引的方式获取对应的值，时间复杂度为O(1)
   * FastThreadLocal 中维护了数组下标
   * netty中的类要配合使用才能达到最大效果