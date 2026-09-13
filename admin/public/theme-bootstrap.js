;(function () {
  try {
    if (typeof Storage === 'undefined' || !window.localStorage) {
      return
    }

    const themeType = localStorage.getItem('sys-theme')
    if (themeType === 'dark') {
      document.documentElement.classList.add('dark')
    }
  } catch (error) {
    console.warn('Failed to apply initial theme:', error)
  }
})()
