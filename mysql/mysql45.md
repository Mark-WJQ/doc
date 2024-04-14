
2. mysql 架构
	* server
		- 连接器 ： 管理链接、验证权限
		- 分析器 ： 分析SQL、检查SQL的合法性、检查表、字段
		- 优化器 ： 生成执行计划，索引选择
		- 执行器：操作引擎，放回结果，判断表权限
	* 引擎
		- 存储数据，提供读写接口
3. 索引
	1. 索引模型
		1. 哈希表
		2. 有序数组
		3. 搜索树
	2. 索引优化
		* 覆盖索引
		* 最左前缀
		* 索引下推：使用索引中字段进行条件过滤，将在server层的过滤下推到存储引擎层
2. 锁
	1. 全局锁
		* 全局锁就是对整个数据库实例加锁。MySQL提供了一个加全局读锁的方法，命令是 Flush tables with read lock (FTWRL)。当你需要让整个库处于只读状态的时候，可以使用这个命令，之后其他线程的以下语句会被阻塞：数据更新语句（数据的增删改）、数据定义语句（包括建表、修改表结构等）和更新类事务的提交语句。
		* 全局锁的典型使用场景是，做全库逻辑备份。也就是把整库每个表都select出来存成文本。
	2. 表级锁
		* 表锁
			- 表锁的语法是 lock tables … read/write
		* 元数据锁（MDL）
			- 另一类表级的锁是MDL（metadata lock)。MDL不需要显式使用，在访问一个表的时候会被自动加上
			- 当对一个表做增删改查操作的时候，加MDL读锁；当要对表做结构变更操作的时候，加MDL写锁。
	3. 行锁
		* 两阶段锁：在InnoDB事务中，行锁是在需要的时候才加上的，但并不是不需要了就立刻释放，而是要等到事务结束时才释放。这个就是两阶段锁协议
			- 如果你的事务中需要锁多个行，要把最可能造成锁冲突、最可能影响并发度的锁尽量往后放。
	2. 死锁
		* 当并发系统中不同线程出现循环资源依赖，涉及的线程都在等待别的线程释放资源时，就会导致这几个线程都进入无限等待的状态，称为死锁。
		* 一种策略是，直接进入等待，直到超时。这个超时时间可以通过参数innodb_lock_wait_timeout来设置。
			- 超时过长业务不可接收，超时过短容易发生误判
		* 另一种策略是，发起死锁检测，发现死锁后，主动回滚死锁链条中的某一个事务，让其他事务得以继续执行。将参数innodb_deadlock_detect设置为on，表示开启这个逻辑。
			- 死锁检测如果遇到热点更新，会消耗大量的资源在检查死锁上
			-
2. 事务隔离
	1. 数据库隔离级别，解决脏读、不可重复读、幻读
		* 读未提交
		* 读已提交
		* 可重复读
		* 串行化
	2. InnoDB里面每个事务有一个唯一的事务ID，叫作transaction id。它是在事务开始的时候向InnoDB的事务系统申请的，是按申请顺序严格递增的。
	2. 而每行数据也都是有多个版本的。每次事务更新数据的时候，都会生成一个新的数据版本，并且把transaction id赋值给这个数据版本的事务ID，记为row trx_id。同时，旧的数据版本要保留，并且在新的数据版本中，能够有信息可以直接拿到它。也就是说，数据表中的一行记录，其实可能有多个版本(row)，每个版本有自己的row trx_id。这些版本是逻辑视图，也就是undo-log
	3. 可重复读的定义，一个事务启动的时候，能够看到所有已经提交的事务结果。但是之后，这个事务执行期间，其他事务的更新对它不可见。
	4. innodb 为每个事务构造了一个数组，叫一致性视图，用来保存在事务启动瞬间还在未提交的事务。并找出低水位，高水位。在这个期间是有事务锁的，不能创建新的事务
		1. 低水位 是指活跃事务的最小id，高水位是最大id
		2. 小于低水位的事务id是已提交的，对于当前事务可见，大于高水位的事务是未来的事务，对于当前事务及时提交了也不可见
		3. 其他事务，如果在活跃事务视图中可以找到也不可见，如果找不到则可见，当前100，eg: 低 96 高 100，\[96,98,100\], 97跟99 不在数组中可见，96,98 在数组中不可见，当然100 是自己可见
	5. 当前读
		1. 当事务中执行 lock in shared mode,for update ,update 时，如果还是按快照读视图那样更新，可能会覆盖其他事务的更新数据，eg：97 更新提交后，100 再更新。
		2. 更新数据都是先读后写的，而这个读，只能读当前的值（最新的已提交的），称为“当前读”（current read）。
		3. 当前读视图下需要读记录加锁，会阻塞其他事务对相同记录的修改
	6. 而读提交的逻辑和可重复读的逻辑类似，它们最主要的区别是：
		* 在可重复读隔离级别下，只需要在事务开始的时候创建一致性视图，之后事务里的其他查询都共用这个一致性视图；
		* 在读提交隔离级别下，每一个语句执行前都会重新算出一个新的视图。

2. 普通索引唯一索引
	1. The change buffer is a special data structure that caches changes to secondary index pages when those pages are not in the buffer pool.
	2. changebuffer 数据库索引修改时，如果内存中没有该页会将该修改存入changebuffer中，在下次读入数据页时，进行合并，主要是针对 二级索引，因为二级索引的更新基本都是无序的，如果每次更新都读取数据页的话，会造成随机读。update 操作会被拆分成delete、insert
	3. 唯一索引用不到changbuffer，因为唯一索引必须读入数据页判断索引是否冲突
	4. changbuffer 的使用场景  写多读少收益大
	5. change buffer 中的修改也会记录到redo log，索引页读入内存的时候会应用change buffer 中的内容到索引页
1. 给字符串字段加索引，考虑点 1. 区分度 2. 空间占用
	1.  全索引，支持区间查询
	2. 前缀索引，可能会有多次回表查询，前缀一样后缀不一样需要回表校验
	3.  hash后再索引， 等值查询友好
2. mysql 抖动
	1. 网络
	2. 数据刷盘，脏页flush，IO瓶颈，导致sql 执行等待
		+ redo 日志写满，需要停了全部写入操作，将redo日志中的修改落盘
		+ buffer pool 中没有空闲页，需要将最近最久未使用的脏页写入磁盘
		+ 解决方案：控制刷盘
			* 关注脏页比例
3. mysql 选错索引
	1. 主要原因是 优化器对索引基数的预估错误
	2. MySQL是怎样得到索引的基数的呢？这里，我给你简单介绍一下MySQL采样统计的方法。
		* 为什么要采样统计呢？因为把整张表取出来一行行统计，虽然可以得到精确的结果，但是代价太高了，所以只能选择“采样统计”。
		* 采样统计的时候，InnoDB默认会选择N个数据页，统计这些页面上的不同值，得到一个平均值，然后乘以这个索引的页面数，就得到了这个索引的基数。
		* 而数据表是会持续更新的，索引统计信息也不会固定不变。所以，当变更的数据行数超过1/M的时候，会自动触发重新做一次索引统计。
		* 在MySQL中，有两种存储索引统计的方式，可以通过设置参数innodb_stats_persistent的值来选择：
			- 设置为on的时候，表示统计信息会持久化存储。这时，默认的N是20，M是10。
			- 设置为off的时候，表示统计信息只存储在内存中。这时，默认的N是8，M是16。
	3. 索引选择异常处理
		* force index
		* 修改SQL，引导使用索引
		* 新建一个合适的索引或删掉误用的索引
4. 表数据删除以后表文件大小不变
	1. 主要是mysql在删除时是标记删除，不会把空闲空间还给操作系统，有新数据插入的时候会直接复用标记删除的页或记录
	2. 如何整理表空洞，通过重建表 Online DDL alter table table_name engine = innodb，相当于新建一个表，然后将记录重新插入新表中，这样插入的记录紧凑，不存在空洞，在数据复制过程中对旧表的操作记录log并在数据复制完成后再应用
	3. MDL 表结构锁
5. count(\*\)
	1. innoDB 引擎是实时扫描每一行的，主要是因为MVVC 的机制，在不同事务中查询count(*)时可能比存在不一致的现象
	2. 性能 count(字段) < count(主键id) < count(1) ≈ count(*)
	3. server层要什么就给什么；InnoDB只给必要的值；现在的优化器只优化了count(*)的语义为“取行数”，其他“显而易见”的优化并没有做。
	4. count(字段) 首先需要取字段，数值复制，如果不是主键的话还需要判断是否为NULL，count(1) 遍历每一行返回一个1，不涉及字段的那些操作，count(*) 不取值，做特殊优化，每一行直接+1
	5. 如果字段有索引的话，可能会通过索引来计数，二级索引比主键索引小
6. redo log、binlog
7. order by 工作方式
	1. sorte buffer  可以指定大小，sort_buffer_size，就是MySQL为排序开辟的内存（sort_buffer）的大小。如果要排序的数据量小于sort_buffer_size，排序就在内存中完成。但如果排序数据量太大，内存放不下，则不得不利用磁盘临时文件辅助排序。主要是归并排序
	3. 排序时有两种情况 一种是 只取排序字段 + rowid，排完以后回表查询需要返回的信息，这样可能会有较多的io；第二种是全字段排序，把所有用到的字段都取出来放到buffer中排序，排好后直接返回，这样是减少回表次数；通过参数 max_length_for_sort_data 控制
		* 如果单行的长度超过这个值，MySQL就认为单行太大，要换一个算法。
8. 查询语句效率低下的原因
	1. 字段上加索引了，但是没走索引或走索引全扫描了
	2. 可能原因，根本上是破坏了索引的有序性，导致查询条件无法按照索引的方式匹配
		1. 在索引字段上使用了函数，where month(t_modified)=7
		2. 发生隐式转换，数据库字段是varchaer，查询时用的 int
		3. 隐式字符编码转换，a表的编码格式utf8,b 表格式utf8mb4 两个表关联查询
9. 查询响应时间长
	1. 从三个方面考虑
		1. 等锁
			1. MDL（metadata locks），表结构锁，执行DDL，DML 是需要先获取MDL，DDL 获取读锁，DML 写锁
			2. 表锁
			3. 行锁，读的时候加 lock in shared mode；
		2. 数据落盘被阻塞
			1. FLUSH TABLES  会锁表,flush关闭表如果flush 语句被阻塞的话，flush本身操作很快
			2. FLUSH TABLES WITH READ LOCK  可读不可改
		3. mvvc导致
			1. 两个事务交替执行，一个事务对一条数据连续更新n次，另一个事物的查询可能需要回溯undo_log n个版本
			2. limit y,1  y很大
10. 幻读
	1. 幻读是指在同一个事务中前后两次查询同一个范围的时候第二次查到了第一次中没有看到的行。
		1. 在可重复读隔离级别下，普通的查询是快照读，是不会看到别的事务插入的数据的。因此，幻读在“当前读”下才会出现。
		2. session B的修改结果，被session A之后的select语句用“当前读”看到，不能称为幻读。幻读仅专指“新插入的行”。
		3. 从语义、数据一致性角度 思考事务执行是否满足RR级别下的ACID
			- 在RR隔离级别下，幻读、脏读、不可重复读是需要避免的
		4. 如何解决幻读
			1. next-key lock 间隙锁和行锁合称next-key lock，前开后闭区间
			2. 间隙锁，前开后开，一般用在二级索引上
11. 加锁规则（默认RR）
	1. 加锁的基本单位是next-lock key
	2. 查找过程中，只有访问到的对象才会加
	3. 索引等值查询时，如果是唯一索引next-lock key会退化成行锁
	4. 索引等值查询时，向右查找最后一个值不满足条件时，next-key lock 退化成间隙锁
		1. *在非唯一索引上进行范围查询加锁时，主键上也会加锁好，需要注意主键的边界*
			* eg: c为非唯一索引，id为主键，select * from t where c = 10 for update;加锁范围（c=5,id=5) 开区间 ,(c=10,id=20),(c=10,id=30),(c=15,id=15) 开区间
			* insert (c=5，id=6) 插入失败，(c=5，id=4) 插入成功，从这个例子中可以看出，在主键上也加了gap锁，为什么加，因为在索引中相同索引值指向的id是有序的，加锁是在索引上进行的，并且通过当前顺序确定加锁范围，如果新插入一条在锁范围内的数据，相当于在破坏锁边界，破坏数据一致性，所以此时也要将左边界上的向右的id加上gap锁 (c=5,id=(5,supernum])，同理右边界上也要加类似的gap(c=15,id=[负无穷,15))
			* 执行 for update时，系统会认为你接下来要更新数据，因此会顺便给主键索引上满足条件的行加上行锁。
	5. 唯一索引上的范围查询会访问到不满足条件的第一个值为止
	6. order desc 会倒排加锁，向左加
12. mysql 提升性能的 损方法
	1. 短连接风暴
		2. 杀线程，占着链接不工作的线程
		2. 减少连接过程的消耗，跳过权限验证
	2. 慢查询
		1. 索引没设计好，加索引，online ddl
		2. 语句没写好，通过rewrite 重写 insert into query_rewrite.rewrite_rules(pattern, replacement, pattern_database) values ("select * from t where id + 1 = ?", "select * from t where id = ? - 1", "db1");
		3. mysql选错索引，force index，同上重写
	3. QPS 突增
		1. 加白名单
		2. 重写语句 select 1
13. mysql 如何保证语句不丢
	1. redo log、binlog
	2. 提交过程 写redo log cache -> 写binlog cache -> 写redo log page cache -> 写binlog page cache -> commit
	2. binlog  写入机制，先写入binlog cache ，在事务提交的时候在写入binlog文件
		1. 每个mysql都维护自己的binlog cache，在事务执行完成之前不会写入binlog文件，如果binlog语句太大会建一个临时文件来存储
		2. write 和fsync的时机，是由参数sync_binlog控制的：
			* sync_binlog=0的时候，表示每次提交事务都只write，不fsync；
			* sync_binlog=1的时候，表示每次提交事务都会执行fsync；
			* sync_binlog=N(N>1)的时候，表示每次提交事务都write，但累积N个事务后才fsync
		3. 如果你想提升binlog组提交的效果，可以通过设置 binlog_group_commit_sync_delay和binlog_group_commit_sync_no_delay_count来实现。
			* binlog_group_commit_sync_delay参数，表示延迟多少微秒后才调用fsync;
			* binlog_group_commit_sync_no_delay_count参数，表示累积多少次以后才调用fsync。
	3. redo log 分两个阶段，prepare 写入buffer，commit 阶段在write到 page cache,最后落盘
		1. redo log cache 是所有线程公用的
		2. 为了控制redo log的写入策略，InnoDB提供了innodb_flush_log_at_trx_commit参数，它有三种可能取值：
			* 设置为0的时候，表示每次事务提交时都只是把redo log留在redo log buffer中;
			* 设置为1的时候，表示每次事务提交时都将redo log直接持久化到磁盘；
			* 设置为2的时候，表示每次事务提交时都只是把redo log写到page cache。
		3. InnoDB有一个后台线程，每隔1秒，就会把redo log buffer中的日志，调用write写到文件系统的page cache，然后调用fsync持久化到磁盘。
			1. *注意，事务执行中间过程的redo log也是直接写在redo log buffer中的，这些redo log也会被后台线程一起持久化到磁盘。也就是说，一个没有提交的事务的redo log，也是可能已经持久化到磁盘的。*
		4. 除了后台线程每秒一次的轮询操作外，还有两种场景会让一个没有提交的事务的redo log写入到磁盘中。
			- 一种是，redo log buffer占用的空间即将达到 innodb_log_buffer_size一半的时候，后台线程会主动写盘。注意，由于这个事务并没有提交，所以这个写盘动作只是write，而没有调用fsync，也就是只留在了文件系统的page cache。
			- 另一种是，并行的事务提交的时候，顺带将这个事务的redo log buffer持久化到磁盘。假设一个事务A执行到一半，已经写了一些redo log到buffer中，这时候有另外一个线程的事务B提交，如果innodb_flush_log_at_trx_commit设置的是1，那么按照这个参数的逻辑，事务B要把redo log buffer里的日志全部持久化到磁盘。这时候，就会带上事务A在redo log buffer里的日志一起持久化到磁盘。
	4. cache -> page cache(write) -> disk(fsync)

		<details>
		<summary>
		日志写入流程图
		</summary>

		```plantuml
			@startuml 
				start
				:开始执行事务;
				while (所有sql语句 ?) is (未执行完)
				:执行next sql;
				:写redo log buffer;
				:写binlog cache;
				endwhile (执行完)
				:redo log prepare write page cache;
				:binlog write page cache (中间会有其他并行事务的redo log 提交);
				:redo log prepare fsync disk(把已经准备好的事务一起提交，减少写盘次数);
				:binlog fsync disk;
				:redo log commit;
				end
			@enduml
		```
		</details>

	5. 提高写入效率，减少io次数
		1. 组提交：group commit,结合上面的流程看，在binlog 从cache write page cache 时会有其他redo log 执行
			* 三个并发事务(trx1, trx2, trx3)在prepare 阶段，都写完redo log buffer，持久化到磁盘,对应的LSN分别是50、120 和160。
				1. trx1是第一个到达的，会被选为这组的 leader；
				2. 等trx1要开始写盘的时候，这个组里面已经有了三个事务，这时候LSN也变成了160；
				3. trx1去写盘的时候，带的就是LSN=160，因此等trx1返回时，所有LSN小于等于160的redo log，都已经被持久化到磁盘；
				4. 这时候trx2和trx3就可以直接返回了。
		2. binlog 组提交的参数
			* binlog_group_commit_sync_delay参数，表示延迟多少微秒后才调用fsync;
			* binlog_group_commit_sync_no_delay_count参数，表示累积多少次以后才调用fsync。

14. 主备一致
	1. binlog_format
		* statement, 原始语句，优点是日志文件小，缺点是 可能造成主从不一致，SQL语句中存在函数时执行不一致，eg: delete where a > and b < order by limit ,a、b上都有索引在主从上可能分配到不同的索引上,
		* row，针对具体的每一行，优点是执行准确，同时恢复数据方便，缺点是对操作的每一行都做记录，日志文件比较大
		* mixed，statement 与 row 结合，mysql执行引擎自行判断应使用那种格式
		*mysqlbinlog 命令查看日志*
	2. 主备复制的流程
		1. 在备库B上通过change master命令，设置主库A的IP、端口、用户名、密码，以及要从哪个位置开始请求binlog，这个位置包含文件名和日志偏移量。
		2. 在备库B上执行start slave命令，这时候备库会启动两个线程，就是图中的io_thread和sql_thread。其中io_thread负责与主库建立连接。
		3. 主库A校验完用户名、密码后，开始按照备库B传过来的位置，从本地读取binlog，发给B。
		4. 备库B拿到binlog后，写到本地文件，称为中转日志（relay log）。
		5. sql_thread读取中转日志，解析出日志里的命令，并执行。
	3. 主备结构
		1. M-S
		2. M-M
			* 存在一个问题循环复制
			- 规定两个库的server id必须不同，如果相同，则它们之间不能设定为主备关系；
			- 一个备库接到binlog并在重放的过程中，生成与原binlog的server id相同的新的binlog；
			- 每个库在收到从自己的主库发过来的日志后，先判断server id，如果跟自己的相同，表示这个日志是自己生成的，就直接丢弃这个日志
15. MySQL 保证高可用
	1. 主备延迟
		1. 与数据同步有关的时间点主要包括以下三个：
			* 主库A执行完成一个事务，写入binlog，我们把这个时刻记为T1;
			* 之后传给备库B，我们把备库B接收完这个binlog的时刻记为T2;
			* 备库B执行完成这个事务，我们把这个时刻记为T3。
		2. 在网络正常的时候，日志从主库传给备库所需的时间是很短的，即T2-T1的值是非常小的。也就是说，网络正常情况下，主备延迟的主要来源是备库接收完binlog和执行完这个事务之间的时间差
			* 主备延迟最直接的表现是，备库消费中转日志（relay log）的速度，比主库生产binlog的速度要慢。
	2. 延迟原因
		1. 备库机器比主库机器配置差、
		2. 备库压力大
		3. 大事务
		4. 大表DDL也是大事务
	3. 高可用策略
		1. 可靠性优先
			在双M结构下，从状态1到状态2切换的详细过程是这样的：会有一段时间的不可写状态
			1. 判断备库B现在的seconds_behind_master，如果小于某个值（比如5秒）继续下一步，否则持续重试这一步；
			2. 把主库A改成只读状态，即把readonly设置为true；
			3. 判断备库B的seconds_behind_master的值，直到这个值变成0为止；
			4. 把备库B改成可读写状态，也就是把readonly 设置为false；
			5. 把业务请求切到备库B。
		2. 可用性优先
			1. 先执行4、5步，可能会造成数据冲突，并且冲突可能发现不了，需要配合binlog_format=row
16. mysql 并行复制
	1. 
17. 主备切换
	1. 基于位点的主备切换
		1. 位点需要人工确定，为了保证数据的准确性，会倾向与向前找一些
		2. 向前找会存在的问题就是新主库与从库的位点重复，造成执行错误
		3. 为了避免错误需要在同步的过程中跳过错误
			1. 遇到一次手动跳过一次
			2. 对指定的错误ignore，只是在切换的过程中设置，同步正常以就不能再设置了
				- 1062错误是插入数据时唯一键冲突；
				- 1032错误是删除数据时找不到行。
	2. 基于gtid的主备切换
		1. GTID的全称是Global Transaction Identifier，也就是全局事务ID，是一个事务在提交的时候生成的，是这个事务的唯一标识。它由两部分组成，格式是：GTID=server_uuid:gno
			* server_uuid是一个实例第一次启动时自动生成的，是一个全局唯一的值；
			* gno是一个整数，初始值是1，每次提交事务的时候分配给这个事务，并加1
		2. 在GTID模式下，每个事务都会跟一个GTID一一对应。这个GTID有两种生成方式，而使用哪种方式取决于session变量gtid_next的值。
			* 如果gtid_next=automatic，代表使用默认值。这时，MySQL就会把server_uuid:gno分配给这个事务。
				1. 记录binlog的时候，先记录一行 SET @@SESSION.GTID_NEXT=‘server_uuid:gno’;
				2. 把这个GTID加入本实例的GTID集合。
			* 如果gtid_next是一个指定的GTID的值，比如通过set gtid_next='current_gtid’指定为current_gtid，那么就有两种可能：
				1. 如果current_gtid已经存在于实例的GTID集合中，接下来执行的这个事务会直接被系统忽略；
				2. 如果current_gtid没有存在于实例的GTID集合中，就将这个current_gtid分配给接下来要执行的事务，也就是说系统不需要给这个事务生成新的GTID，因此gno也不用加1。
18. 读写分离
	1. 过期读，由于主从可能存在延迟，客户端执行完一个更新事务后马上发起查询，如果查询选择的是从库的话，就有可能读到刚刚的事务更新之前的状态。
	2. 如何避免过期读
		1. 强制走主库，但可能造成主库压力太大
		2. sleep 方案
		2. 通过判断主从延迟时间，如果延迟时间为0，则读从库，否则读主库，seconds_behind_master是否已经等于0
		3. 等主库位点方案，事务提交后可以拿到当前binlog的file，pos，拿着他们去从库上看有没有执行到  select master_pos_wait(file, pos[, timeout]);
		3. 通过等gtid，事务提交后可以拿到gtid，拿着gtid去从库中检查是否已经同步  select wait_for_executed_gtid_set(gtid_set, 1);
		4. 配合semi-sync，半同步，主库提交事务前需要先同步从库，收到从库ack后才可以提交事务，会把事务时间拉长
19. 如何判断数据库是否正常
	1. select 1  只能验证mysql执行器正常，验证不到执行引擎异常, 比如查询线程全部被占
	2. select * from t 无法验证存储空间已满，存储满后无法写binlog日志
	3. update  timestamp  更新时间戳，无法验证主情况
	3. update  timestamp by server_id 多主验证
20. 误删数据是否需要跑路，预防与恢复
	1. 权限控制
	2. 代码上线前，必须经过SQL审计。
	3. 把sql_safe_updates参数设置为on。这样一来，如果我们忘记在delete或者update语句中写where条件，或者where条件里面没有包含索引字段的话，这条语句的执行就会报错。
	2. 做预案
		* 备份数据
			1. 删除表的操作，可以先改表名，观察业务系统是否有异常
			2. 数据库定期全量备份，binlog 备份
		* 恢复脚本
			1. 在备份数据库的基础上，利用备份binlog 恢复数据，记得跳过删除语句
			2. 加快备份速度，利用多线程复制的特性，在利用备份数据恢复一台数据库实例后，将这个实例设置成线上备库的从库，如果线上备库的binlog日志已经清除，就补充备份的binlog日志
			3. 备库延迟执行，如果设置一个备库延迟执行 3600s,在一个小时之内发现删除错误，就可以利用这个备库只恢复最近一个小时的数据
		* 修改脚本
21. kill
	1. mysql 的kill命令不是直接杀死线程，是向该线程发送信号量，线程收到信号量以后还要做恢复、释放资源的工作，所以kill的过程会比较长
	1. kill query
	2. kill connection
	*show PROCESSLIST*
22. 查询结果集过大，数据库如何处理？内存放不下？
	1. net_buffer,net_buffer_size=16K
	2. 数据查询后会一条一条写入net_buffer中，写满后发送客户端，发送后再读剩下的数据进入net_buffer,周而复始
	3. 全表扫描，查询结果集大可能意味着进行了全表扫描
		1. buffer pool 中数据页的替换算法是LRU，如果一致读取磁盘中的数据，那么lru算法会失效，缓存命中率会很低，sql执行时长较长
		2. 优化LRU，链表按5 young:3 old，刚读出来的数据放在old区，如果一秒钟之后还有人访问则放到young区，这样可以避免全链表失效，不过对于新缓存不太友好，因为如果全表扫描，old区page还的太快，导致其他正常查询的缓存页也会很快被淘汰
23. join
	```sql
		CREATE TABLE `t2` (
			`id` int(11) NOT NULL,
			`a` int(11) DEFAULT NULL,
			`b` int(11) DEFAULT NULL,
			PRIMARY KEY (`id`),
			KEY `a` (`a`)
		) ENGINE=InnoDB;
		create table t1 like t2;
	```
	1. join 的执行过程,执行语句 select * from t1 straight_join t2 on (t1.a=t2.b);
		1. Simple Nested-Loop Join  
			* 从t1 表中查出一条符合条件的记录 r1
			* 从 r1 中取出字段 a,到t2 中找到 b = a 的记录 r2，t2全表扫描
			* where 条件过滤
			* r1 跟 r2 组成结果集
			* 重复前三步，直到找出所有结果集
		2. Block Nested-Loop Join
			* 有一个join_buffer,  join_buffer_size  设置其大小
			* 从t1表中查询记录，将满足条件的记录 放入join buffer 中
			* 扫描t2,取出每一行与join buffer 中记录匹配组成结果集, 对join buffer 中的记录扫描
			* 如果t1中满足条件的记录太多，join buffer 中一次放不下，则每次取一部分，重复前两步
			* 每次取出来的t1中的记录，可以认为是 block
		3. Index Nested-Loop Join
			* 执行语句 select * from t1 straight_join t2 on (t1.a=t2.a);
			* 语句执行过程跟 Simple Nested-Loop Join 是一样的，唯一不同的是这次查询使用到被驱动表 t2 的 索引 a
		4. hash join
			* 在join buffer 中创建 hash 表
			* 遍历被驱动表，通过hash与join buffer 中的记录匹配，把 join buffer 的遍历优化成 hash 查找
			* 构造结果集
		5. join 优化
			* Multi-Range Read: 回表查询时，先在read_rnd_buffer中对主键进行排序，这样在查询数时就会尽最大可能避免随机读，MRR
			* BKA 匹配被驱动表时，不是一行行进行匹配，而是将排好序的字段批量传出去匹配数据，利用MRR特性
		6. left join : 在MySQL里，NULL跟任何值执行等值判断和不等值判断的结果，都是NULL。这里包括， select NULL = NULL 的结果，也是返回NULL。
			* 驱动表选择
				- 一般来说使用左表驱动
				- mysql 优化器会对sql进行优化，left join 优化使用 join，再进行驱动表的选择
					+ 比如 where 中有过滤条件的 select * from a left join b on(a.f1=b.f1) where (a.f2=b.f2);/*Q2*/
			* 过滤条件在on 与 where 中的区别
				- 先执行on的条件进行两个表的关联
				- 在执行where对关联结果进行过滤
				- 在join 中on跟where结果是一样的，在left join 跟 right join 中执行顺序会影响结果
	2. join 语法使用小表驱动
		1. 小表是相对来说的，join前先预估哪个表符合条件的记录少，或是相同行数下哪个表需要加载列少，哪个就是驱动表
24. 临时表
	1. 特性
		1. 建表语法是create temporary table …。
		2. 一个临时表只能被创建它的session访问，对其他线程不可见。所以，图中session A创建的临时表t，对于session B就是不可见的。
		3. 临时表可以与普通表同名。
		4. session A内有同名的临时表和普通表的时候，show create语句，以及增删改查语句访问的是临时表。
		5. show tables命令不显示临时表。
	2. 临时表的应用场景
		1. union 流程
			*  union 取两个表子查询的并集，有重复行只保留一行
			*  创建一个内存临时表，以第一个查询的字段为准，建立唯一索引，全量字段
			*  执行第一个查询，将结果写入临时表中
			*  执行第二个查询，将结果一次插入临时表中，如果冲突则跳过
			*  从临时表中按行取出数据，返回结果集，删除临时表
			*union all 不需要使用临时表，将每个查询的结果按行返回即可*
		2. group by

			```sql
			select id%10 as m, count(*) as c from t1 group by m;

			使用 explain 发现用到索引 a

			```
			* 创建内存临时表，表里有两个字段 m,c 主键是m
			* 扫描表t1的索引a，取出主键id，计算 id%10 记为 x
			* 如果临时表中没有主键为x的行，就插入一个记录(x,1);如果表中有主键为x的行，就将x这一行的c值加1；
			* 返回结果集
		3. group by 优化-索引
			1.  要解决group by语句的优化问题，你可以先想一下这个问题：执行group by语句为什么需要临时表？group by的语义逻辑，是统计不同的值出现的个数。但是，由于每一行的id%100的结果是无序的，所以我们就需要有一个临时表，来记录并统计结果。
			2.  如果可以确保输入的数据是有序的，那么计算group by的时候，就只需要从左到右，顺序扫描，依次累加
				* 当碰到第一个1的时候，已经知道累积了X个0，结果集里的第一行就是(0,X);
				* 当碰到第一个2的时候，已经知道累积了Y个1，结果集里的第二行就是(1,Y);
				```sql
				alter table t1 add column z int generated always as(id % 100), add index(z);
				select z, count(*) as c from t1 group by z;
				```

		4. group by 优化-直接排序
			1. 如果我们明明知道，一个group by语句中需要放到临时表上的数据量特别大，却还是要按照“先放到内存临时表，插入一部分数据后，发现内存临时表不够用了再转成磁盘临时表”，看上去就有点儿傻
			2. MySQL有没有让我们直接走磁盘临时表的方法呢？
			3. 在group by语句中加入SQL_BIG_RESULT这个提示（hint），就可以告诉优化器：这个语句涉及的数据量很大，请直接用磁盘临时表。
			4. select SQL_BIG_RESULT id%100 as m, count(\*) as c from t1 group by m; 的执行流程就是这样的：
				* 初始化sort_buffer，确定放入一个整型字段，记为m；
				* 扫描表t1的索引a，依次取出里面的id值, 将 id%100的值存入sort_buffer中；
				* 扫描完成后，对sort_buffer的字段m做排序（如果sort_buffer内存不够用，就会利用磁盘临时文件辅助排序）
				* 排序完成后，就得到了一个有序数组。

		5. distinct 与 group by 的区别
			1. group by 如果没有聚合函数，其实执行过程是一样的

25. 自增主键
	1. 属性
		* auto_increment_offset 起始值
		* auto_increment_increment   步长
		* innodb_autoinc_lock_mode
			- 这个参数的值被设置为0时，表示采用之前MySQL 5.0版本的策略，即语句执行结束后才释放锁；
			- 这个参数的值被设置为1时：普通insert语句，自增锁在申请之后就马上释放；类似insert … select这样的批量插入数据的语句，自增锁还是要等语句结束后才被释放；
			- 这个参数的值被设置为2时，所有的申请自增主键的动作都是申请后就释放锁。
	2. 不连续原因
		* 唯一索引冲突
		* 事务回滚
		* 批量插入，最后可能申请多了
			- insert …… select from  不知道要插入多少数据，如果每插入一条就申请一次主键就效率太低，所以mysql做了批量申请id优化，每次申请主键都是上一次的两倍
				+ 第一次申请一个
				+ 第二次申请两个
				+ 第三次申请4个
				+ …… 以此类推
	3. 锁
		* insert … select 是很常见的在两个表之间拷贝数据的方法。你需要注意，在可重复读隔离级别下，这个语句会给select的表里扫描到的记录和间隙加读锁。主要binlog 同步时多个事务对同一个表操作产生脏数据，binlog_format=stament
		* 而如果insert和select的对象是同一个表，则有可能会造成循环写入。这种情况下，我们需要引入用户临时表来做优化。
		* insert 语句如果出现唯一键冲突，会在冲突的唯一值上加共享的next-key lock(S锁)。因此，碰到由于唯一键约束导致报错后，要尽快提交或回滚事务，避免加锁时间过长。
		* insert 新插入一条数据会在唯一索引加记录锁，其他事务中插入相同的值锁等待



	





