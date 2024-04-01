1. NioEventLoop 执行run方法
2. run 方法一直自旋
3. 调用selector.select(),检查当前是否有I/O事件
4. 如果有I/O事件，执行selector.selectKeys()
5. 遍历处理SelectionKeys
6. key 中是否有可读事件
7. 自旋，从channel中读取字节,直到不可读
8. 将读取到的字节使用ChannelHandler处理
9. 如果有拆包、粘包需要处理，使用 ByteToMessageDecoder
10. ByteToMessageDecoder 中维护了 Cumulator 将多次读到的字节进行累加
11. 每累加一次，调用一次decode
12. 如果decode解析出对象，则将对象交给pipeline下一个ChannelHandler处理，反序列化
13. 执行业务逻辑
    14. 结束自旋
        ```plantuml
            @startuml
                title channel read
            
                boundary NioEventLoop as nel
                boundary Selector
                entity NioByteUnsafe as unsafe
                entity NioSocketChannel as nssc
                entity RecvByteBufAllocator.Handle as allocHandle
                control ChannelPipeline as cp
                control ChannelHandlerContext as chc
                entity ChannelInboundHandler as handler
                entity javaSocketChannel as javaCh
            
            
                nel -> Selector:selectedKeys
                group processSelectedKey
                Selector --> nel : 响应准备好的key
                nel -> nssc:unsafe
                nssc --> nel : 响应chann绑定的unsafe
                nel -> unsafe:read
                end group
                unsafe --> unsafe:recvBufAllocHandle,创建接收处理器allocHandle
                loop allocHandle.continueReading()
                unsafe -> allocHandle:allocate
                allocHandle --> unsafe:创建接收数据的ByteBuf
                unsafe -> nssc : doReadBytes,入参是接收数据的ByteBuf
                nssc -> javaCh : read
                javaCh --> nssc: 将读取到的字节信息写入到指定的ByteBuf中
                alt 本次读取的字节数 <=0
                unsafe -> unsafe:释放接收数据的ByteBuf
                alt 本次读取的字节数 < 0
                unsafe -> unsafe: 表示对方发送的close事件，设置 close=true
                end
                end
                unsafe -> cp : fireChannelRead
                cp -> chc : invokeChannelRead
                chc -> handler :(head~tail).channelRead
                note right
                读取字节信息后在handler中进行转码，主要是协议解析、反序列化、拆包、粘包等
                end note
                handler -> handler : ByteToMessageDecoder.decode
                note over handler
                ByteToMessageDecoder 子类基于它可以很方便的实现拆包与粘包的操作，每个channel都单独绑定一个实例，带状态的Cumulator
                使用Cumulator(累加器)，将每次读取进来的bytebuf进行合并，合并完后尝试decode，如果可以解析出所需的对象则调用下一个channelHandler进行业务处理，否则不做任何操作
                decode操作根据协议读取指定的大小的字节数、或者读完以后直接反序列化成对象等
                end note
            
            
                end loop
                unsafe -> cp : fireChannelReadComplete
                note right
                驱动hanndler处理ChannelReadComplete
                end note
            
                alt close == true
                group closeOnRead
                alt 允许半关
                unsafe -> nssc : shutdownInput
                nssc -> javaCh : shutdownInput
                unsafe -> cp:fireUserEventTriggered(ChannelInputShutdownEvent.INSTANCE)
                else 否则
                unsafe -> nssc : close
                end
                end
                end
                @enduml
        ```