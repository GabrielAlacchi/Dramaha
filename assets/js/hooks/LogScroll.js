
const scrollDown = (ul) => {
  ul.parentElement.scroll(0, ul.offsetHeight);
};


export const LogScroll = {
  mounted() {
    this.pinToBottom = true;
    this.scrollContainer = this.el.parentElement;

    this.scrollContainer.addEventListener('scroll', () => {
      console.log(this.scrollContainer.scrollTop);
      if (this.scrollContainer.scrollTop < this.el.offsetHeight - this.scrollContainer.offsetHeight) {
        this.pinToBottom = false;
      } else {
        this.pinToBottom = true;
      }
    });

    scrollDown(this.el);
  },
  updated() {
    if (this.pinToBottom) {
      scrollDown(this.el);
    }
  }
}
