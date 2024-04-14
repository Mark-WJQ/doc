1. kafka
   * 可用性： 分布式架构多副本即使部分节点发生故障，整个系统也可以使用；自动平衡机制，broker加入或故障，可以实现负载均衡与故障恢复；持久化和日志复制机制
   * 可靠性：多副本、日志持久化存储
   * 高性能：批量提交消费消息、顺序读写磁盘、pagecache（利用操作系统的页缓存，如果在读写速率相当的情况下只需要读写pagecache，基本不会操作文件）、分区、零拷贝（直接从pagecache发送到socket channel） 
2. 核心概念
   * Broker
   * Consume Group
   * Topic
   * 分区（Partition）
   * 副本（Replica）
   * 分区平衡：分区的leader replica均衡分布在broker上
     * AR：已分配副本
     * PR：优先副本
     * ISR：同步副本
3. 控制器
   * leader broker
   * 控制器选举，利用zk，建立结点/controller
   * 故障转移，leader故障，重新选举leader
   * 代理上线，broker上下线
     * /brokers/ids
   * 主题管理
     * 创建主题
       * /brokers/topics 下创建主题对应的子节点
       * TopicChangeListener 操作新增的主题，分区、副本状态转化、分区leader的分配、分区存储日志的创建
     * 删除主题
       * /admin/delete_topics 创建删除主题的子节点
   * 分区管理
     * 分区自动平衡
       * 定时检查分区是否市区平衡
     * 分区重新分配
4. 协调器:协调消费者工作分配的
   * 消费者协调器
     * 更新消费者缓存的MetaData
     * 向组协调器申请加入组
     * 消费者加入组后的相应处理
     * 请求离开消费组
     * 向组协调器提交消费偏移量
     * 通过心跳保持与组协调器连接感知
     * 被组协调器选为leader的消费者协调器，负责消费者与分区的映射关系分配，并将分配结果发送给组协调器
     * 非leader的消费者，通过消费者协调器与组协调器同步分配结果
   * 组协调器
     * 在与之连接的消费者者选出leader
     * 下发leader消费者返回的消费者分区分配结果给所有的消费者
     * 管理消费者的消费偏移量提交，保存在kafka的内部主题中
     * 和消费者心跳保持，知道哪些消费者存活，哪些
5. 副本管理
   * ISR中的节点，一旦宕机或中断时间太长leader会把同步副本从isr中剔除，只有在ISR中的副本才有资格被选举为leader
     * 存活的节点要维持和zk的session连接，通过zk的心跳机制实现
     * flower副本要与leader副本保持同步，不能落后太多，默认是30s
   * LEO（Log end offset）。表示每个分区最后一条消息的位置，每个副本都有LEO
   * HW(High Watermark),一个分区所有副本中最小的那个LEO
   * 消费者在消费时只有小于HW的的消息才可以被消费
   * LEO与HW的同步，flower在向leader请求拉取消息时会将当前副本LEO与HW携带，同时响应请求时会将leader的LEO与HW响应给flower，根据规则设置leader与flower的LEO与HW
6. 日志管理 
   * kafka消息是以日志文件的形式存储。不同主题下不同分区的消息是分开存储的。同一个分区不同副本也是以日志的形式，分布在不同的broker上存储
   * 在程序逻辑上，日志是以副本为单位存储，每个副本对应一个log对象。但实际在物理上，一个log又划分为多个logSegment进行存储
   * logSegment代表一组逻辑上的文件，三个文件名一样，命名规则是.log文件中第一条消息的前一条消息偏移量，也成为基础偏移量，左边补0补齐20位
     * .log 存储消息
     * .index 存储消息的索引，稀疏索引
     * .timeIndex 时间索引文件，通过时间戳做索引
   * 日志定位
     * 根据offset定位logsegment（kafka将基础偏移量作为key存储在ConcurrentSkipListMap）
     * 根据logsegm的index文件查找距离目标offset最近的被索引offset的poisition x
     * 找到logsegment的.log文件中的x的位置，向下逐条查找,找到目标offset的消息