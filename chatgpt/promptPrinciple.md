### 提示词原则
1. 明确而具体的提示
   * write clear and specific instructions,clear != short
   * 你应该通过提供尽可能清洗和具体的说明来表达您希望模型做什么
     * 策略
       * 使用分隔符清楚指示输入的不同部分
       * 要求结构化的输出
       * 要求模型检查条件是否满足，如果不满足条件，可以不进行测试
       * 给一些示例
2. given the model time to think
    * 策略
      * 指定完成任务的步骤
      * 下结论之前，先让大模型自己计算出答案，然后在于给定的答案进行比较，而不是直接判定答案的正确与否
        * instruct the model to work out its own solution before rushing to a conclusion(rushing to a conclusion 急于下结论)
3. 模型限制
   * 幻觉（hallucination），模型会编造听起来合理但实际并不真实的事情，当他在尝试回答有关晦涩问题
   * 减少幻觉：先从文档中找到相关信息，然后引用这些信息回答，并且将答案追溯到源文档
4. 迭代提示（Iterative Prompt Development）
   * prompt guidelines
     * be clear and specific
     * analyze why result does not give desired output
     * redifine the idea and the prompt
     * repeat
   * iterative Process
     * try something
     * analyze where the result does not give what you want
     * clarify instructions,give more time to think
     * refine prompts with a batch of examples