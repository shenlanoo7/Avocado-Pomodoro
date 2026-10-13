(function (root) {
  class Timer {
    constructor() { this.state = 'idle'; this.name = ''; this.mode = 'focus'; this.pendingNotes = []; }
    start(name, now = Date.now(), _preferences = undefined, focusMinutes = 25) {
      if (!Number.isInteger(focusMinutes) || focusMinutes < 1 || focusMinutes > 180) throw new RangeError('Minutes must be an integer from 1 to 180');
      this.focusSeconds = focusMinutes * 60;
      this.startFocus(name, now);
    }
    startFocus(name, now) {
      this.name = name.trim() || 'Untitled Session';
      this.mode = 'focus'; this.state = 'running'; this.startedAt = now;
      this.duration = this.focusSeconds ?? 1500; this.deadline = now + this.duration * 1000;
      this.id = String(now) + '-' + Math.random().toString(36).slice(2);
      this.elapsedSeconds = 0; this.endedEarly = false; this.resolved = false; this.awaitingChoice = false; this.overtime = false;
      this.pauseSequence = 0; this.pauseNoteSaved = false; this.pauseNoteDraft = '';
    }
    remaining(now = Date.now()) {
      if (this.state === 'completed') return 0;
      if (this.state === 'paused') return this.pausedRemaining;
      const seconds = Math.ceil((this.deadline - now) / 1000);
      return this.overtime ? seconds : Math.max(0, seconds);
    }
    pause(now = Date.now()) {
      if (this.state !== 'running') return;
      this.pausedRemaining = this.remaining(now); this.state = 'paused';
      this.pausedAt = now; this.pauseElapsedSeconds = this.duration - this.pausedRemaining;
      this.pauseSequence = (this.pauseSequence || 0) + 1;
      this.pauseEventId = this.id + '-pause-' + this.pauseSequence;
      this.pauseNoteSaved = false; this.pauseNoteDraft = '';
    }
    resume(now = Date.now()) {
      if (this.state !== 'paused') return;
      this.deadline = now + this.pausedRemaining * 1000; this.state = 'running';
    }
    keepGoing() {
      if (this.state !== 'completed' || !this.awaitingChoice || this.mode !== 'focus') return false;
      this.awaitingChoice = false; this.overtime = true; this.state = 'running';
      return true;
    }
    break(now = Date.now()) {
      this.mode = 'break'; this.state = 'running'; this.duration = 300; this.awaitingChoice = false; this.overtime = false;
      this.deadline = now + this.duration * 1000; this.elapsedSeconds = 0; this.endedEarly = false;
      this.startedAt = now; this.id = String(now) + '-rest-' + Math.random().toString(36).slice(2);
    }
    advance(now = Date.now()) {
      if (this.state !== 'completed' || this.mode !== 'focus' || this.endedEarly || this.resolved) return false;
      if (this.mode === 'focus') {
        this.pendingNotes.push({id:this.id, name:this.name, startedAt:this.startedAt, completedAt:this.completedAt, plannedSeconds:this.duration, elapsedSeconds:this.elapsedSeconds, endedEarly:this.endedEarly, note:''});
        this.resolved = true;
        this.break(now);
      }
      return true;
    }
    finish(now = Date.now()) {
      if (!['running', 'paused'].includes(this.state) && !this.awaitingChoice) return false;
      this.elapsedSeconds = this.awaitingChoice ? this.duration : Math.max(0, this.duration - this.remaining(now));
      this.awaitingChoice = false;
      this.endedEarly = this.elapsedSeconds < this.duration;
      this.completedAt = now; this.state = 'completed';
      return true;
    }
    static restore(raw) {
      try {
        const s = JSON.parse(raw);
        const validPlan = n => Number.isInteger(n) && n >= 60 && n <= 10800 && n % 60 === 0;
        const validCompletion = n => {
          const planned = n.plannedSeconds ?? n.duration ?? 1500;
          if(n.endedEarly === true && n.elapsedSeconds >= planned)return false;
          return validPlan(planned) && Number.isFinite(n.startedAt) && n.startedAt >= 0 && Number.isFinite(n.completedAt) && n.completedAt >= n.startedAt && n.completedAt <= 253402300799000 && Number.isInteger(n.elapsedSeconds) && n.elapsedSeconds >= 0 && n.elapsedSeconds <= (n.completedAt - n.startedAt) / 1000 + 1 && n.elapsedSeconds * 1000 <= n.completedAt - n.startedAt + 1000 && (n.endedEarly === undefined || typeof n.endedEarly === 'boolean') && (n.endedEarly === true || n.elapsedSeconds >= planned && n.completedAt - n.startedAt >= planned * 1000);
        };
        if (s.focusSeconds !== undefined && !validPlan(s.focusSeconds)) throw Error();
        if (!['idle', 'running', 'paused', 'completed'].includes(s.state)) throw Error();
        if (s.state !== 'idle' && (!Number.isFinite(s.deadline) || !Number.isFinite(s.startedAt) || !validPlan(s.duration) || typeof s.name !== 'string' || typeof s.id !== 'string')) throw Error();
        if (s.state === 'paused' && (!Number.isFinite(s.pausedRemaining) || (!s.overtime && s.pausedRemaining < 0) || s.pausedRemaining > s.duration)) throw Error();
        if (s.state !== 'idle' && (s.mode === 'focus' ? s.duration !== (s.focusSeconds ?? 1500) : s.mode !== 'break' || s.duration > 3600)) throw Error();
        if (s.state !== 'idle' && s.elapsedSeconds !== undefined && (!Number.isInteger(s.elapsedSeconds) || s.elapsedSeconds < 0 || (!s.overtime && s.elapsedSeconds > s.duration))) throw Error();
        if (s.state === 'completed' && s.mode === 'focus' && s.elapsedSeconds !== undefined && !validCompletion(s)) throw Error();
        if (s.pendingNotes !== undefined && (!Array.isArray(s.pendingNotes) || s.pendingNotes.some(n => !n || typeof n.id !== 'string' || typeof n.name !== 'string' || !validCompletion(n)))) throw Error();
        for (const key of ['restMinutes','sequence','groupActive','groupCompleted','focusCompleted','restKind']) delete s[key];
        return Object.assign(new Timer(), s);
      } catch { return new Timer(); }
    }
    tick(now = Date.now()) {
      if (this.state === 'running' && !this.overtime && now >= this.deadline) {
        this.state = 'completed'; this.completedAt = this.deadline;
        this.elapsedSeconds = this.duration; this.endedEarly = false; this.awaitingChoice = this.mode === 'focus';
        return true;
      }
      return false;
    }
  }
  root.Timer = Timer;
  if (typeof module !== 'undefined') module.exports = { Timer };
})(typeof window !== 'undefined' ? window : globalThis);
