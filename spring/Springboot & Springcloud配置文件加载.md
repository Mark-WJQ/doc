### Springboot & Springcloud配置文件加载  
[TOC]  
#### 背景
1. 调研微服务框架
2. 根据作用不同，配置需要分离
3. 服务不复杂，暂时不需要配置中心,使用本地配置文件的方式
4. 使用jasypt对配置加密遇到一些问题
#### 目的
1. 清楚配置文件的加载过程
2. 能够在遇到配置加载的问题快速定位解决
#### 过程
##### Springboot
1. springboot的配置文件加载在[官网](https://docs.spring.io/spring-boot/docs/current/reference/html/spring-boot-features.html#boot-features-external-config)说的很清楚，我做一遍搬运工再加一些细节实现
2. 说一下加载配置的代码
    1. 首先配置加载以后是以PropertySource为载体的，一个PropertySource标识一个配置来源或配置文件(eg:系统属性，命令行属性等)
    2. 在代码中对配置的一些操作一般都是通过Environment对象进行的，Environment包含一个PropertySource的有序列表，可以解决配置的优先级
    3. Springboot应用在启动时通常是通过调用SpringApplication.run() 方法进行，配置的加载要在应用最前面部分进行，即在准备Environment阶段进行。在SpringApplication 中有如下代码
        ```java
            public ConfigurableApplicationContext run(String... args) {
               // 省略代码、
                ApplicationArguments applicationArguments = new DefaultApplicationArguments(args);
                ConfigurableEnvironment environment = prepareEnvironment(listeners, applicationArguments);  //配置加载主要在这个方法中进行
                configureIgnoreBeanInfo(environment);
                //省略代码
            }


            private ConfigurableEnvironment prepareEnvironment(SpringApplicationRunListeners listeners,ApplicationArguments applicationArguments) {
                // Create and configure the environment
                ConfigurableEnvironment environment = getOrCreateEnvironment();
                configureEnvironment(environment, applicationArguments.getSourceArgs());
                ConfigurationPropertySources.attach(environment);
                listeners.environmentPrepared(environment);  //监听者模式，在这里会触发一个事件 ApplicationEnvironmentPreparedEvent，相应的监听器在监听到该事件后便会做相应的操作
                //省略代码
                return environment;
            }

        ```
        跟踪以上代码发现，配置信息的加载实际上是在监听者中进行的，即 ConfigFileApplicationListener，
        ```java
        public class ConfigFileApplicationListener implements EnvironmentPostProcessor, SmartApplicationListener, Ordered {
               /**
               * 该监听者对哪些事件感兴趣
               **/
            @Override
            public boolean supportsEventType(Class<? extends ApplicationEvent> eventType) {
                return ApplicationEnvironmentPreparedEvent.class.isAssignableFrom(eventType)
                        || ApplicationPreparedEvent.class.isAssignableFrom(eventType);
            }

            //监听到事件
            @Override
            public void onApplicationEvent(ApplicationEvent event) {
                if (event instanceof ApplicationEnvironmentPreparedEvent) {
                    onApplicationEnvironmentPreparedEvent((ApplicationEnvironmentPreparedEvent) event);  //对事件进行处理
                }
                //省略代码
            }

            //对事件进行详细处理
            private void onApplicationEnvironmentPreparedEvent(ApplicationEnvironmentPreparedEvent event) {
                List<EnvironmentPostProcessor> postProcessors = loadPostProcessors();
                postProcessors.add(this);
                AnnotationAwareOrderComparator.sort(postProcessors);
                for (EnvironmentPostProcessor postProcessor : postProcessors) {
                    postProcessor.postProcessEnvironment(event.getEnvironment(), event.getSpringApplication());
                }
            }

            @Override
            public void postProcessEnvironment(ConfigurableEnvironment environment, SpringApplication application) {
                addPropertySources(environment, application.getResourceLoader());
            }

            /**
             + Add config file property sources to the specified environment.
             + @param environment the environment to add source to
             + @param resourceLoader the resource loader
             + @see #addPostProcessors(ConfigurableApplicationContext)
             */
            protected void addPropertySources(ConfigurableEnvironment environment, ResourceLoader resourceLoader) {
                RandomValuePropertySource.addToEnvironment(environment);
                new Loader(environment, resourceLoader).load();
            }

        }
        ```
        从代码中可以看出，该监听器在监听事件后，实际调用的 EnvironmentPostProcessor，通过对EnvironmentPostProcessor进行扩展可以对ConfigurableEnvironment进行定制化处理。而ConfigFileApplicationListener是实现了EnvironmentPostProcessor，所以配置文件的加载也就在这个监听器中进行，从上边的代码看到，调用链接到Loader中，Loader是ConfigFileApplicationListener的内部类，实际加载工作都在Loder中进行。
        ```java

        private class Loader {

                void load() {
                    FilteredPropertySource.apply(this.environment, DEFAULT_PROPERTIES, LOAD_FILTERED_PROPERTY,
                            (defaultProperties) -> {
                                this.profiles = new LinkedList<>();
                                this.processedProfiles = new LinkedList<>();
                                this.activatedProfiles = false;
                                this.loaded = new LinkedHashMap<>();
                                initializeProfiles();
                                while (!this.profiles.isEmpty()) {
                                    Profile profile = this.profiles.poll();  //每次加载完一个document会将active.profile,include.profile 添加到this.profiles，这样能够加载到所有指定的profile
                                    if (isDefaultProfile(profile)) {
                                        addProfileToEnvironment(profile.getName());
                                    }
                                    load(profile, this::getPositiveProfileFilter,
                                            addToLoaded(MutablePropertySources::addLast, false));
                                    this.processedProfiles.add(profile);
                                }
                                load(null, this::getNegativeProfileFilter, addToLoaded(MutablePropertySources::addFirst, true));
                                addLoadedPropertySources();
                                applyActiveProfiles(defaultProperties);
                            });
                }

                private void load(Profile profile, DocumentFilterFactory filterFactory, DocumentConsumer consumer) {
                    getSearchLocations().forEach((location) -> {     //获取配置文件地址并遍历，如果通过属性spring.config.location指定，则使用指定的路径，否则按序查找默认位置：file:./config/,file:./config/*/,file:./,classpath:/config/,classpath:/，如果spring.config.additional-location 有值，会与前面获取到的路径合并
                        boolean isDirectory = location.endsWith("/");
                        Set<String> names = isDirectory ? getSearchNames() : NO_SEARCH_NAMES;  //获取配置文件名称，如果spring.config.name指定文件名，则使用否则使用默认文件名application
                        names.forEach((name) -> load(location, name, profile, filterFactory, consumer)); //遍历文件名加载文件
                    });
                }


                private void load(String location, String name, Profile profile, DocumentFilterFactory filterFactory,DocumentConsumer consumer) {
                    if (!StringUtils.hasText(name)) { //未指定的文件名，认为文件路径中已经包含文件名,直接进行加载
                        for (PropertySourceLoader loader : this.propertySourceLoaders) {
                            if (canLoadFileExtension(loader, location)) {
                                load(loader, location, profile, filterFactory.getDocumentFilter(profile), consumer);
                                return;
                            }
                        }
                        //省略抛出异常代码
                    }
                    Set<String> processed = new HashSet<>();
                    for (PropertySourceLoader loader : this.propertySourceLoaders) {  //遍历不同的属性加载器(yml,yaml,properties,xml)
                        for (String fileExtension : loader.getFileExtensions()) {
                            if (processed.add(fileExtension)) {
                                loadForFileExtension(loader, location + name, "." + fileExtension, profile, filterFactory,
                                        consumer);
                            }
                        }
                    }
                }


                private void loadForFileExtension(PropertySourceLoader loader, String prefix, String fileExtension,
                    Profile profile, DocumentFilterFactory filterFactory, DocumentConsumer consumer) {
                    DocumentFilter defaultFilter = filterFactory.getDocumentFilter(null);
                    DocumentFilter profileFilter = filterFactory.getDocumentFilter(profile);
                    if (profile != null) {  
                    //如果profile不为空，则优先加载指定profile的配置文件，eg:profile=dev,prefix=classpath://appliaction,fileExtension=.yml,则文件名classpath://appliaction-dev.yml
                        // Try profile-specific file & profile section in profile file (gh-340)
                        String profileSpecificFile = prefix + "-" + profile + fileExtension;
                        load(loader, profileSpecificFile, profile, defaultFilter, consumer);
                        load(loader, profileSpecificFile, profile, profileFilter, consumer);
                        // Try profile specific sections in files we've already processed
                        for (Profile processedProfile : this.processedProfiles) {
                            if (processedProfile != null) {
                                String previouslyLoaded = prefix + "-" + processedProfile + fileExtension;
                                load(loader, previouslyLoaded, profile, profileFilter, consumer);
                            }
                        }
                    }
                    // 加载不指定profile的文件，eg：classpath://appliaction.yml，profile可能在文件中分离
                    load(loader, prefix + fileExtension, profile, profileFilter, consumer);
                }

                /**
                + 加载文件
                */
                private void load(PropertySourceLoader loader, String location, Profile profile, DocumentFilter filter,DocumentConsumer consumer) {
                    Resource[] resources = getResources(location);
                    for (Resource resource : resources) {
                        try {
                           //省略判断代码
                            String name = "applicationConfig: [" + getLocationName(location, resource) + "]"; //PropertySource name
                            List<Document> documents = loadDocuments(loader, name, resource); //load配置文件,一个配置文件中可以指定多个profile，所以会返回 List<Document>，在yml文件中使用---分割多个profile
                            if (CollectionUtils.isEmpty(documents)) {
                                continue;
                            }
                            List<Document> loaded = new ArrayList<>();
                            for (Document document : documents) {
                                if (filter.match(document)) {//主要是判断profile是否是activeprofile或为空
                                    addActiveProfiles(document.getActiveProfiles());  //获取spring.profiles.active,并入队，加载该profile中的配置信息
                                    addIncludedProfiles(document.getIncludeProfiles()); //获取spring.profiles.include,并入队，加载该profile中的配置信息
                                    loaded.add(document);
                                }
                            }
                            Collections.reverse(loaded);
                            if (!loaded.isEmpty()) {
                                loaded.forEach((document) -> consumer.accept(profile, document)); //将加载好的符合条件的配置暂存
                            }
                        }
                        catch (Exception ex) {
                            //异常处理
                        }
                    }
                }
        }
        ```
        通过对以上代码分析，我们可以知道配置文件的加载流程 
        ```

        项目启动SpringApplication.run() 
        --> prepareEnvironment() 
        -->SpringApplicationRunListeners.environmentPrepared(environment);(发送ApplicationEnvironmentPreparedEvent) 
        -->ConfigFileApplicationListener.onApplicationEvent()(监听到event) 
        -->ConfigFileApplicationListener.postProcessEnvironment() 
        -->Loader.load() 
        -->Loader.loadForFileExtension()
        ```
##### Springcloud
1. 在以上文档中我们可以知道Springboot的配置文件加载方式，其实Springcloud是对Springboot进行封装，简单点说cloud执行了两次boot的流程。
2. 新增加监听器BootstrapApplicationListener，该监听器的执行优先级比ConfigFileApplicationListener高，所以在cloud应用启动时先执行BootstrapApplicationListener
```java
    public class BootstrapApplicationListener implements ApplicationListener<ApplicationEnvironmentPreparedEvent>, Ordered{

            //监听事件
            @Override
            public void onApplicationEvent(ApplicationEnvironmentPreparedEvent event) {
                ConfigurableEnvironment environment = event.getEnvironment();
                //是否需要执行启动流程
                if (!environment.getProperty("spring.cloud.bootstrap.enabled", Boolean.class,
                        true)) {
                    return;
                }
                // don't listen to events in a bootstrap context
                //表示正在初始化bootstrapcontext，直接返回执行后续listener
                if (environment.getPropertySources().contains(BOOTSTRAP_PROPERTY_SOURCE_NAME)) {
                    return;
                }
                ConfigurableApplicationContext context = null;
                //可通过该属性指定启动上下文中加载的文件
                String configName = environment
                        .resolvePlaceholders("${spring.cloud.bootstrap.name:bootstrap}");
                for (ApplicationContextInitializer<?> initializer : event.getSpringApplication()
                        .getInitializers()) {
                    if (initializer instanceof ParentContextApplicationContextInitializer) {
                        context = findBootstrapContext(
                                (ParentContextApplicationContextInitializer) initializer,
                                configName);
                    }
                }
                if (context == null) {
                    //bootstrap context 启动
                    context = bootstrapServiceContext(environment, event.getSpringApplication(),
                            configName);
                    event.getSpringApplication()
                            .addListeners(new CloseContextOnFailureApplicationListener(context));
                }

                apply(context, event.getSpringApplication(), environment);
            }



        private ConfigurableApplicationContext bootstrapServiceContext(
                    ConfigurableEnvironment environment, final SpringApplication application,
                    String configName) {
                StandardEnvironment bootstrapEnvironment = new StandardEnvironment();
                MutablePropertySources bootstrapProperties = bootstrapEnvironment
                        .getPropertySources();
                //清除所有配置信息
                for (PropertySource<?> source : bootstrapProperties) {
                    bootstrapProperties.remove(source.getName());
                }
                //获取指定启动配置位置
                String configLocation = environment
                        .resolvePlaceholders("${spring.cloud.bootstrap.location:}");
                //额外文件夹
                String configAdditionalLocation = environment
                        .resolvePlaceholders("${spring.cloud.bootstrap.additional-location:}");
                Map<String, Object> bootstrapMap = new HashMap<>();
                //配置文件名称，会在后续的ConfigFileApplicationListener 中使用
                bootstrapMap.put("spring.config.name", configName);
                // if an app (or test) uses spring.main.web-application-type=reactive, bootstrap
                // will fail
                // force the environment to use none, because if though it is set below in the
                // builder
                // the environment overrides it
                bootstrapMap.put("spring.main.web-application-type", "none");
                if (StringUtils.hasText(configLocation)) {
                    //配置文件，会在后续的ConfigFileApplicationListener 中使用
                    bootstrapMap.put("spring.config.location", configLocation);
                }
                if (StringUtils.hasText(configAdditionalLocation)) {
                     //配置文件，会在后续的ConfigFileApplicationListener 中使用
                    bootstrapMap.put("spring.config.additional-location",
                            configAdditionalLocation);
                }
                //将组织好的初始化加载信息放入启动属性中
                bootstrapProperties.addFirst(
                        new MapPropertySource(BOOTSTRAP_PROPERTY_SOURCE_NAME, bootstrapMap));
                //将当前环境中PropertySource放入启动属性中，主要是系统属性，命令行属性等
                for (PropertySource<?> source : environment.getPropertySources()) {
                    if (source instanceof StubPropertySource) {
                        continue;
                    }
                    bootstrapProperties.addLast(source);
                }
                //通过SpringApplicationBuilder 新建一个SpringApplication，并且填充一些属性
                // TODO: is it possible or sensible to share a ResourceLoader?
                SpringApplicationBuilder builder = new SpringApplicationBuilder()
                        .profiles(environment.getActiveProfiles()).bannerMode(Mode.OFF)
                        .environment(bootstrapEnvironment)
                        // Don't use the default properties in this builder
                        .registerShutdownHook(false).logStartupInfo(false)
                        .web(WebApplicationType.NONE);
                final SpringApplication builderApplication = builder.application();
                if (builderApplication.getMainApplicationClass() == null) {
                    // gh_425:
                    // SpringApplication cannot deduce the MainApplicationClass here
                    // if it is booted from SpringBootServletInitializer due to the
                    // absense of the "main" method in stackTraces.
                    // But luckily this method's second parameter "application" here
                    // carries the real MainApplicationClass which has been explicitly
                    // set by SpringBootServletInitializer itself already.
                    builder.main(application.getMainApplicationClass());
                }
                if (environment.getPropertySources().contains("refreshArgs")) {
                    // If we are doing a context refresh, really we only want to refresh the
                    // Environment, and there are some toxic listeners (like the
                    // LoggingApplicationListener) that affect global static state, so we need a
                    // way to switch those off.
                    builderApplication
                            .setListeners(filterListeners(builderApplication.getListeners()));
                }
                //类似于MainClass，通过BootstrapImportSelectorConfiguration 可以将spring.factories中 org.springframework.cloud.bootstrap.BootstrapConfiguration 指定的类先加载，做一些cloud 的前置加载工作
                builder.sources(BootstrapImportSelectorConfiguration.class);
                //嵌套调用SpringApplication.run(),本次boostrap完成后，会继续执行之前未完成的上下文
                final ConfigurableApplicationContext context = builder.run();
                // gh-214 using spring.application.name=bootstrap to set the context id via
                // `ContextIdApplicationContextInitializer` prevents apps from getting the actual
                // spring.application.name
                // during the bootstrap phase.
                context.setId("bootstrap");
                // Make the bootstrap context a parent of the app context
                addAncestorInitializer(application, context);
                // It only has properties in it now that we don't want in the parent so remove
                // it (and it will be added back later)
                //移除name=bootstrap 的 PropertySource,该属性源是为了加载bootstrap context 添加的，已经完成使命，如果不移除会影响后续application context 中配置的加载，主要是因为他的优先级很高，会影响spring.config.name等的取值
                bootstrapProperties.remove(BOOTSTRAP_PROPERTY_SOURCE_NAME);
                //bootstrap context 初始化完成以后合并属性，为后续的Application context 添加属性，此时会把加载的 configName文件合并
                mergeDefaultProperties(environment.getPropertySources(), bootstrapProperties);
                return context;
            }

            /**
            + 向applicationcontext中添加一些信息
            **/
            private void apply(ConfigurableApplicationContext context,SpringApplication application, ConfigurableEnvironment environment) {
                if (application.getAllSources().contains(BootstrapMarkerConfiguration.class)) {
                    return;
                }
                application.addPrimarySources(Arrays.asList(BootstrapMarkerConfiguration.class));
                @SuppressWarnings("rawtypes")
                Set target = new LinkedHashSet<>(application.getInitializers());
                target.addAll(
                        getOrderedBeansOfType(context, ApplicationContextInitializer.class));
                application.setInitializers(target);
                addBootstrapDecryptInitializer(application);
            }


    }
```
3. 由以上代码可以看出，cloud实际上是通过一个优先级较高的Listener来嵌套生成一个bootstrap context，从而能够提前加载一些cloud相关的一些配置，准备cloud的环境，bootstrap context 加载完成后，会继续执行application context的加载，也就是上边的springBoot的加载过程
4. 我们可以得出的调用流程是
```

项目启动SpringApplication.run() 
--> prepareEnvironment() 
-->SpringApplicationRunListeners.environmentPrepared(environment);(发送ApplicationEnvironmentPreparedEvent) 
    -->BootstrapApplicationListener.onApplicationEvent()(监听到event) 
    -->判断是否正在执行初始化bootstrap context 阶段，若是则跳过该listener，执行后续的listener
    -->BootstrapApplicationListener.bootstrapServiceContext()(生成bootstrap context) 
        -->设置bootstrapEnvironment,spring.config.name,spring.config.location等属性
        -->SpringApplicationgBuilder.run() 
            -->SpringApplication.run() 
-->ConfigFileApplicationListener.onApplicationEvent()(监听到event) 
-->ConfigFileApplicationListener.postProcessEnvironment() 
-->Loader.load() 
-->Loader.loadForFileExtension()

```


