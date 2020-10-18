import * as moment from 'moment';


export const TimeBar = {
  mounted() {
    const expiryMs = parseInt(this.el.dataset.expiryMs);
    const expiryTime = moment().add(expiryMs, 'milliseconds');
    const durationMs = parseInt(this.el.dataset.durationSeconds) * 1000;
    this.interval = null;

    this.filler = this.el.children[0];
    this.counter = this.el.children[1].children[0];

    this.startTimebarLoop(expiryTime, durationMs);
  },
  beforeDestroy() {
    if (this.interval !== null) {
      console.log("Clearing timer interval");
      clearInterval(this.interval);
    }
  },
  startTimebarLoop(expiryMoment, durationMs) {
    this.interval = setInterval(() => {
      const time = moment();

      const millisecondsLeft = expiryMoment - time;

      const secondsLeft = Math.round(millisecondsLeft / 1000).toFixed(0);
      if (this.counter.innerText !== secondsLeft) {
        this.counter.innerText = secondsLeft;
      }

      const percentage = millisecondsLeft / durationMs * 100;

      if (percentage < 20) {
        this.filler.classList.add('hurry');
      }

      this.filler.style.width = `${percentage.toFixed(1)}%`;
    }, 100)
  }
}
