1. 核心概念
    1. channel
        * channelpiplen
          + channelInBoundHandler
          + channelOutBoundHandler
          + ByteBuf
   2. netty 自带handler
    * 拆包器
      * FixedLengthFrameDecoder
      * LengthFieldBasedFrameDecoder
      * DelimiterBasedFrameDecoder、
      * LineBasedFrameDecoder
      * 自定解码器
        * Header：魔数、版本、协议、序列化算法、报文类型、状态、保留字段、报文长度
        * body：报文内容
      * TCP发送数据是一段一段发送的，在数据传输中会存在粘包（多个请求在一段数据中发送）跟分包（一个请求分成多多段），并且在TCP是流式数据传输，没有办法直接分辨出数据是否终止，那netty在消费数据时是如何做的
        * ByteToMessageDecoder 维护了 Cumulator ，Channel 不断读入数据，Cumulator 将读进来的数据进行合并，合并一次触发一次解码，解码后移除已读数据
        * io.netty.channel.nio.AbstractNioByteChannel.NioByteUnsafe#read
    * 协议栈
      * http(2)
      * dns
      * ssl
      * redis
      * mqtt
      * stomp
      * 工具
    * 编解码
      * base64
      * marshalling
      * xml
      * string
      * protobuf
      * json
      * compress
    * 工具
      * idleHandler
      * traffic
      * logging
      * Ip rule
      * DynamicAddress
      * HashedWheelTimer 定时任务：时间轮
      * Mpsc.newMpscQueue 多生产者单消费者队列
2. 高性能
   1. 线程模型
      * NioEventLoopGroup
        * 字面意思是一组NioEventLoop
      * NioEventLoop(只包含一个线程)
        ```plantuml
        title NioEventLoop 执行过程
        start
        :NioEventLoop初始化;
        :调用者提交task,任务入队;
        note
        nio.netty.util.concurrent.SingleThreadEventExecutor#execute(java.lang.Runnable)
        end note
        if (线程已启动?) is (yes) then
        :cas设置线程启动状态;
        :创建并启动线程;
        :将loop中的线程变量赋值为新启动线程;
        :执行SingleThreadEventExecutor.this.run()方法;
        note
        run方法在NioEventLoop中覆写,while-true执行
        end note
        endif
        :notify线程执行;
        :run方法执行;
        while (true)
        :计算selector策略;
        note
         1. 查看当前线程队列中是否有任务
         2. 没有的话返回策略SELECT=-1
         3. 否则返回 selector.selectNow()
            end note
            if (策略为SELECT?) is (yes) then
            if (调度队列中有任务?) is (yes) then
            :selector.select(timeout);
            else (no)
            :selector.select();
            endif
            endif
            if (IO计数>0?) is (yes) then
            :处理IO事件;
            endif
            note
         1. IO计数是select策略的数字或select
         2. 处理read、write、accept、connect
            end note
            :运行队列中任务;
            note
         1. 将调度队列中到期任务提取到线程队列中
         2. 执行线程队列中任务
         3. 执行tailQueue中的任务
            end note
            endwhile
            stop
        ```
   2. FastThreadLocal
   3. 内存
      * [内存分配算法](https://juejin.cn/post/7051200855415980069)
        * 主要从两个方面解决问题，1. 分配效率，池化，缓存 2. 碎片程度，内部碎片、外部碎片
        * chunk、run（整数倍page）、page(默认8k)、subpage(16b-28K)
      * UnpooledHeadBytebuf
      * unpooledDirectBytebuf
      * pooledHeadBytebuf
      * pooledDirectBytebuf
      * ResourceLeakDetector-SimpleLeakAwareByteBuf|AdvancedLeakAwareByteBuf
        * 内存泄漏检测，主要是利用WeakReference对象回收时，将引用放入ReferenceQueue中，通过检测queue发现内存是否泄露
        * 主要是针对Bytebuf，正常调用release方法后，内存检测对象会销毁，否则就会检测到
   4. 零拷贝
      * DirectBytebuf 直接内存
      * CompositeBytebuf 组合多个Bytebuf
      * Unpooled.wrappedBuffer  直接将byte数组封装成Bytebuf
      * ByteBuf.slice 操作与 Unpooled.wrappedBuffer 相反，slice 操作可以将一个 ByteBuf 对象切分成多个 ByteBuf 对象，切分过程中不会产生内存拷贝，底层共享一个 byte 数组的存储空间。
      * Netty 使用 FileRegion 实现文件传输，FileRegion 底层封装了 FileChannel#transferTo()
   4. Recycler
      * ThreadLocal 存储回收的对象
      * LocalPool 存储数据结构
        * DefaultHandle 实际存储被回收对象，绑定了线程
        * batch：ArrayDeque<DefaultHandle<T>>  存储本线程回收的对象，初始化的handle
        * pooledHandles：MessagePassingQueue<DefaultHandle<T>> 存储其他线程回收的对象，这个queue支持多生产者单消费者，无锁设计
        * 当本线程获取对象时如果从batch中获取不到，则从pooledHandles 拉取一定数量的对象到batch中，否则新建Handle
