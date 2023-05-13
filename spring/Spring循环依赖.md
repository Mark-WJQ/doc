#### Spring 循环依赖
1. Spring的循环依赖
    * Spring 的循环依赖主要是是指，两个类互相引用，在IOC注入时，互相创建引用。有两种依赖方式：属性注入依赖，构造方法注入依赖
    * 如何解决？
    * 对于属性注入依赖Spring通过三重缓存的机制来解决，类实例化以后在内存中的引用不会变化，剩下的只是注入一些属性,如果是构造器注入依赖则无解
    ```java

    /** Cache of singleton objects: bean name to bean instance. */
    private final Map<String, Object> singletonObjects = new ConcurrentHashMap<>(256);

    /** Cache of singleton factories: bean name to ObjectFactory. */
    private final Map<String, ObjectFactory<?>> singletonFactories = new HashMap<>(16);

    /** Cache of early singleton objects: bean name to bean instance. */
    private final Map<String, Object> earlySingletonObjects = new ConcurrentHashMap<>(16);

    /**
    * singletonObjects          缓存已经初始化完成的bean
    * earlySingletonObjects     缓存正在初始中，且产生循环引用的bean
    * singletonFactories        缓存正在初始化的org.springframework.beans.factory.ObjectFactory
    **/
    @Nullable
    protected Object getSingleton(String beanName, boolean allowEarlyReference) {
        // Quick check for existing instance without full singleton lock
        Object singletonObject = this.singletonObjects.get(beanName);
        if (singletonObject == null && isSingletonCurrentlyInCreation(beanName)) {
            singletonObject = this.earlySingletonObjects.get(beanName);
            if (singletonObject == null && allowEarlyReference) {
                synchronized (this.singletonObjects) {
                    // Consistent creation of early reference within full singleton lock
                    singletonObject = this.singletonObjects.get(beanName);
                    if (singletonObject == null) {
                        singletonObject = this.earlySingletonObjects.get(beanName);
                        if (singletonObject == null) {
                            ObjectFactory<?> singletonFactory = this.singletonFactories.get(beanName);
                            if (singletonFactory != null) {
                                singletonObject = singletonFactory.getObject();
                                this.earlySingletonObjects.put(beanName, singletonObject);
                                this.singletonFactories.remove(beanName);
                            }
                        }
                    }
                }
            }
        }
        return singletonObject;
    }


    // 方法doCreateBean 中将实例化的bean，包装进 ObjectFactory 放进 singletonFactories


    protected Object doCreateBean(String beanName, RootBeanDefinition mbd, @Nullable Object[] args)
            throws BeanCreationException {

        // Instantiate the bean.
        BeanWrapper instanceWrapper = null;
        if (mbd.isSingleton()) {
            instanceWrapper = this.factoryBeanInstanceCache.remove(beanName);
        }
        if (instanceWrapper == null) {
            //创建实例，创建策略有工厂方法，构造器注入，简单创建
            //org.springframework.beans.factory.annotation.AutowiredAnnotationBeanPostProcessor#determineCandidateConstructors  查找构造器注入方法=
            instanceWrapper = createBeanInstance(beanName, mbd, args);
        }
        Object bean = instanceWrapper.getWrappedInstance();
        …………
        // Eagerly cache singletons to be able to resolve circular references
        // even when triggered by lifecycle interfaces like BeanFactoryAware.
        boolean earlySingletonExposure = (mbd.isSingleton() && this.allowCircularReferences &&
                isSingletonCurrentlyInCreation(beanName));
        if (earlySingletonExposure) {
            //将实例化的bean包装成ObjectFactory,并缓存
            addSingletonFactory(beanName, () -> getEarlyBeanReference(beanName, mbd, bean));
        }

        // Initialize the bean instance.
        Object exposedObject = bean;
        try {
            //将依赖的的类初始化并注入
           // org.springframework.beans.factory.annotation.AutowiredAnnotationBeanPostProcessor#postProcessProperties
            populateBean(beanName, mbd, instanceWrapper);
            //初始化
            //Initialize the given bean instance, applying factory callbacks
            //as well as init methods and bean post processors.
            //org.springframework.boot.context.properties.ConfigurationPropertiesBindingPostProcessor#postProcessBeforeInitialization  注入属性 @ConfigurationProperties
            exposedObject = initializeBean(beanName, exposedObject, mbd);
        }
        catch (Throwable ex) {
            if (ex instanceof BeanCreationException && beanName.equals(((BeanCreationException) ex).getBeanName())) {
                throw (BeanCreationException) ex;
            }
            else {
                throw new BeanCreationException(
                        mbd.getResourceDescription(), beanName, "Initialization of bean failed", ex);
            }
        }

       …………

        return exposedObject;
    }

    protected void addSingletonFactory(String beanName, ObjectFactory<?> singletonFactory) {
        Assert.notNull(singletonFactory, "Singleton factory must not be null");
        synchronized (this.singletonObjects) {
            if (!this.singletonObjects.containsKey(beanName)) {
                this.singletonFactories.put(beanName, singletonFactory);
                this.earlySingletonObjects.remove(beanName);
                this.registeredSingletons.add(beanName);
            }
        }
    }

    ```

    ```plantuml
    @startuml
        title: doCreateBean
        start
        :对象实例化;
        partition 创建三级缓存{
        :singletonFactories.put(FactoryBean);
        :三级缓存中的FactoryBean 主要是为对象创建代理;
        }
        partition populated{
        :属性填充;
        :依赖注入，递归调用getBean;
        note
        InstantiationAwareBeanPostProcessor.postProcessPropertyValues 子类实现IOC注入
        CommonAnnotationBeanPostProcessor.postProcessPropertyValues 执行注入@Resource
        AutowiredAnnotationBeanPostProcessor.postProcessPropertyValues  注入注解 @Autowired，@Value
        在依赖注入的过程中会获取依赖对象，如果发生循环依赖，
        那么在获取依赖对象时，会从singletonFactories中获取，此时会执行FactoryBean，
        如果依赖对象存在代理，则会在FactoryBean中执行代理过程，部分BeanPostProcessorsAfterInitialization提前执行
        end note
        }
        partition 对象初始化{
        :执行aware;
        note
        BeanNameAware,BeanClassLoaderAware,BeanFactoryAware
        其他Aware执行：ApplicationContextAwareProcessor
        end note
        :applyBeanPostProcessorsBeforeInitialization;
        :invokeInitMethods:postConstrouct或afterPropertiesSet;
        :applyBeanPostProcessorsAfterInitialization: 其中包含代理对象的创建;
        note
        所有代理相关的创建类都继承自此
        AbstractAutoProxyCreator.earlyProxyReferences
        中维护了先前已经创建的代理对象
        end note
        }

        if (循环依赖且产生代理对象) then (yes)
        :返回代理对象;
        else 
        :返回创建好的对象;
        endif
        end
        @enduml
    
    ```

    ```plantuml
    @startuml
        title:getBean
        partition 获取缓存bean{
            :singletonObjects.get(beanName);
            if (一级缓存存在) then (yes)
            :返回实例对象;
            elseif (实例正在创建中) then (yes)
            :earlySingletonObjects.get(beanName);
            if(二级缓存存在) is (yes) then
            :返回实例对象;
            elseif(allowEarlyReference) then(yes)
            :三级缓存singletonFactory = singletonFactories.get(beanName);
            if (singletonFactory ！= null) is (yes) then
            :singletonFactory.getObject;
            :earlySingletonObjects.put;
            :singletonFactories.remove;
            else (no)
            :null;
            endif
            else
            :null;
            endif
            else
            :null;
            endif
        }
        if (缓存bean存在) then (yes)

        else
        partition 创建实例{
        :获取bean definition;
        :getDependsOn;
        if (单例模式?) is (yes) then
        partition 单例创建过程{
            :标记创建中singletonsCurrentlyInCreation.add(beanName);
            :createBean();
            :清除创建中标记singletonsCurrentlyInCreation.remove(beanName);
            :singletonObjects.put(beanName, singletonObject)
            singletonFactories.remove(beanName)
            earlySingletonObjects.remove(beanName)
            registeredSingletons.add(beanName);
        }
        else (no)
        partition 原型模式创建{
        :创建前处理：在线程上下文中标记创建中;
        :createBean();
        :创建后处理：清除创建标记;
        }
        endif
        }
        endif
        :响应实例;
        end
        @enduml
    ```
