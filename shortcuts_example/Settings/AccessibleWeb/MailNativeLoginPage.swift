enum MailNativeLoginPage {
    static let source = #"""
(() => {
  if (window.top !== window || location.protocol !== 'https:' || location.port || document.readyState !== 'complete') return 'wait';
  const config = __RIVO_MAIL_LOGIN__;
  const host = location.hostname, path = location.pathname;
  const visible = element => !!element && element.getClientRects().length > 0 &&
    getComputedStyle(element).visibility === 'visible';
  const findVisible = (selector, root = document) => Array.from(root.querySelectorAll(selector)).find(visible);
  if (config.inboxHosts.includes(host)) {
    if (findVisible('input[type=password],dialog,[role=dialog]')) return 'wait';
    if (config.provider === 'naver' && !document.querySelector('.wrap .contents_area .mail_list_wrap,.wrap .main_header .menu_title')) return 'wait';
    // Kakao Mail renders its signed-out redirect from an initially empty app shell.
    if (config.provider === 'kakao' && !document.querySelector('#root a[href],#root button')) return 'wait';
    return 'content';
  }

  let form, id, password, submit;
  if (config.provider === 'naver' && location.origin === 'https://nid.naver.com') {
    const captchaForm = document.getElementById('frmNIDLogin');
    const audioChallenge = captchaForm?.method === 'post' &&
      captchaForm.action === 'https://nid.naver.com/nidlogin.rcaptcha' &&
      captchaForm.querySelector('#voice') && captchaForm.querySelector('#chptcha');
    if (path === '/nidlogin.rcaptcha' || audioChallenge || findVisible('#captcha,#chptcha,iframe[src*=captcha i]')) return 'captcha';
    if (path !== '/nidlogin.login' || findVisible('input[autocomplete=one-time-code],dialog,[role=dialog]')) return 'challenge';
    form = document.getElementById('frmNIDLogin');
    if (!form) return 'challenge';
    if (form.method !== 'post' || form.action !== 'https://nid.naver.com/nidlogin.login') return 'challenge';
    id = form.querySelector('input#id[autocomplete=username]');
    password = form.querySelector('input#pw[autocomplete=current-password]');
    submit = findVisible('#loginBtn_row,#loginBtn_column', form);
    if (!id || !password || !submit) return 'challenge';
    if (config.submitted) {
      if (window.__rivoNativeMailAttempt) return 'wait';
      const retry = [...form.querySelectorAll('.form_message')]
        .some(message => visible(message) && /^(다시\s*로그인해\s*주세요|please (?:sign|log) in again|再度ログインしてください)[.!。]?$/i.test(message.textContent.trim()));
      if (!retry) return 'challenge';
      if (!config.credentials) return 'retry';
    }
    if (config.credentials && (document.visibilityState !== 'visible' || password.value ||
        (id.value && id.value !== config.credentials.identifier))) return 'challenge';
  } else if (config.provider === 'nate') {
    if (host === 'xo.nate.com' && path.toLowerCase() === '/mnate/login.sk') {
      form = document.querySelector('form#nate_login');
      id = form?.querySelector('#nateId');
      password = form?.querySelector('#natePw');
    } else if (host === 'home.mail.nate.com' && path === '/login/login.html') {
      form = document.querySelector('form#f_login');
      id = form?.querySelector('input#ID');
      password = form?.querySelector('input#PASSWD');
    } else return 'wait';
    if (!form || form.method !== 'post' || (form.hasAttribute('action') && new URL(form.action).origin !== location.origin)) return 'failed';
    submit = findVisible('input#nateSubmitButton[type=submit],button.btn_login', form);
  } else if (['daum','kakao'].includes(config.provider) && host === 'accounts.kakao.com') {
    if (path !== '/login' && !path.startsWith('/login/')) {
      return config.submitted && findVisible('input[autocomplete=one-time-code],#dkaptcha') &&
        !findVisible('input[type=password]') ? 'challenge' : 'wait';
    }
    id = findVisible('input[name=loginId]');
    form = id?.form;
    password = form?.querySelector('input[name=password]');
    submit = form && findVisible('button[type=submit].submit', form);
    if (form && new URL(form.action).origin !== location.origin) return 'failed';
  } else return 'wait';

  if (!form || !visible(id) || !visible(password) || !submit) return 'wait';
  if (id.form !== form || password.form !== form || submit.form !== form ||
      !['text','email'].includes(id.type) || password.type !== 'password' ||
      id.disabled || id.readOnly || password.disabled || password.readOnly) return 'failed';
  if (findVisible('iframe[src*=captcha i],#dkaptcha,input[autocomplete=one-time-code],dialog,[role=dialog]')) return 'failed';
  if (config.provider !== 'naver' && config.submitted && findVisible('.form_message.error,.desc_error,[role=alert]')) return 'rejected';
  if (!config.credentials) return submit.disabled ? 'wait' : 'ready';
  if (window.__rivoNativeMailAttempt === config.credentials.attempt) return 'submitted';

  const set = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value').set;
  for (const [field,value] of [[id,config.credentials.identifier],[password,config.credentials.password]]) {
    set.call(field,value);
    field.dispatchEvent(new Event('input',{bubbles:true}));
    field.dispatchEvent(new Event('change',{bubbles:true}));
  }
  if (submit.disabled || !submit.isConnected) return 'failed';
  window.__rivoNativeMailAttempt = config.credentials.attempt;
  submit.click();
  return 'submitted';
})()
"""#
}
