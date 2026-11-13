const DISCUSSION = /不要查|不用查|别查|不查|不看|不想查|不想看|不要看|别看|不用看|不用导航|不需要查|不需要看|不需要定位|不定位|不要导航|不需要导航|不要定位|别定位|别打开|不要执行|不要获取|别搜索|不要搜索|先别|暂时别|取消查询|停止查询|这个词|这个表达|这句话|怎么翻译|如何翻译|什么是天气|天气的定义|预报的原理|什么意思|怎么解释|是什么原理|怎么实现|能不能查|可以查吗|能查吗|假如|假设|如果我要|如果我说|^[“"].*[”"]$/;
export function executableText(text) {
  return String(text ?? "").split(/[，,。；;！？!?\n]/).filter(clause => clause.trim() && !DISCUSSION.test(clause)).join("，");
}
export function isDiscussionRequest(text) {
  return DISCUSSION.test(String(text ?? "")) && !executableText(text);
}
