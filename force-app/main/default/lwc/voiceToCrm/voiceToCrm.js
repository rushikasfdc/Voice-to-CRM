import { LightningElement, api, wire, track } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import parseVoiceInput from '@salesforce/apex/VoiceToCrmController.parseVoiceInput';
import executeActions from '@salesforce/apex/VoiceToCrmController.executeActions';
import OPP_NAME from '@salesforce/schema/Opportunity.Name';
import OPP_STAGE from '@salesforce/schema/Opportunity.StageName';
import OPP_AMOUNT from '@salesforce/schema/Opportunity.Amount';
import OPP_CLOSE_DATE from '@salesforce/schema/Opportunity.CloseDate';
import OPP_PROBABILITY from '@salesforce/schema/Opportunity.Probability';
import ACCOUNT_NAME from '@salesforce/schema/Opportunity.Account.Name';

const OPP_FIELDS = [OPP_NAME, OPP_STAGE, OPP_AMOUNT, OPP_CLOSE_DATE, OPP_PROBABILITY, ACCOUNT_NAME];

const ACTION_CONFIG = {
    update: { icon: '⚡', color: '#6366f1' },
    activity: { icon: '📞', color: '#06b6d4' },
    contact: { icon: '👤', color: '#10b981' },
    role: { icon: '🔗', color: '#14b8a6' },
    task: { icon: '📋', color: '#f59e0b' },
    event: { icon: '📅', color: '#8b5cf6' }
};

const SIRI_CANVAS_LARGE = 180;
const SIRI_CANVAS_SMALL = 48;

export default class VoiceToCrm extends LightningElement {
    @api recordId;

    // Widget expand/collapse
    @track expanded = false;

    // Voice state: idle, listening, transcribing, parsing, confirming, confirmed, done
    state = 'idle';
    listenTime = 0;
    transcript = '';
    displayedTranscript = '';
    @track parsedActions = [];
    elapsedTime = '0.0';

    // Internal refs
    _recognition = null;
    _timerInterval = null;
    _animFrame = null;
    _phase = 0;
    _typewriterIdx = 0;
    _typewriterInterval = null;
    _confirmStartTime = null;
    _currentCanvasSize = 0;

    // ─── Wire: Get Opportunity Data ───
    @wire(getRecord, { recordId: '$recordId', fields: OPP_FIELDS })
    opportunity;

    get oppName() {
        return getFieldValue(this.opportunity.data, OPP_NAME) || 'Opportunity';
    }
    get oppStage() {
        return getFieldValue(this.opportunity.data, OPP_STAGE) || '';
    }
    get accountName() {
        return getFieldValue(this.opportunity.data, ACCOUNT_NAME) || '';
    }

    // ─── Expand / Collapse ───
    get isCollapsed() { return !this.expanded; }
    get isExpanded() { return this.expanded; }

    handleExpand() {
        this.expanded = true;
    }

    handleCollapse() {
        // Only allow collapse if not mid-process (listening/transcribing/parsing/confirmed)
        if (this.state === 'idle' || this.state === 'confirming' || this.state === 'done') {
            this.expanded = false;
            if (this.state !== 'idle') {
                this.handleReset();
            }
        }
    }

    // ─── Computed Properties ───
    get isIdle() { return this.state === 'idle'; }
    get isListening() { return this.state === 'listening'; }
    get isTranscribing() { return this.state === 'transcribing'; }
    get isParsing() { return this.state === 'parsing'; }
    get isConfirming() { return this.state === 'confirming'; }
    get isConfirmed() { return this.state === 'confirmed'; }
    get isDone() { return this.state === 'done'; }

    get showOrb() { return this.state === 'idle' || this.state === 'listening'; }
    get showTranscript() { return this.state === 'transcribing' || this.state === 'parsing'; }
    get showActions() { return this.state === 'confirming' || this.state === 'confirmed' || this.state === 'done'; }

    get actionCount() { return this.parsedActions.length; }

    get truncatedTranscript() {
        return this.transcript.length > 80 ? this.transcript.substring(0, 80) : this.transcript;
    }

    get formattedTime() {
        const mins = Math.floor(this.listenTime / 60);
        const secs = String(this.listenTime % 60).padStart(2, '0');
        return `${mins}:${secs}`;
    }

    get statusDotClass() {
        let cls = 'status-dot';
        if (this.state === 'idle') cls += ' dot-idle';
        else if (this.state === 'done') cls += ' dot-done';
        else cls += ' dot-active';
        return cls;
    }

    get statusLabelClass() {
        return this.state === 'done' ? 'status-label done-label' : 'status-label';
    }

    get statusLabel() {
        const labels = {
            idle: 'Voice Update',
            listening: 'Listening...',
            transcribing: 'Transcribing...',
            parsing: 'Parsing actions...',
            confirming: `${this.actionCount} actions found`,
            confirmed: 'Updating Salesforce...',
            done: 'All done!'
        };
        return labels[this.state] || '';
    }

    get micButtonClass() {
        return this.state === 'listening' ? 'mic-btn mic-recording' : 'mic-btn mic-idle';
    }

    get visibleActions() {
        return this.parsedActions.map((action, index) => {
            const config = ACTION_CONFIG[action.type] || ACTION_CONFIG.update;
            const checked = this.state === 'confirmed' || this.state === 'done';
            return {
                ...action,
                id: `action-${index}`,
                icon: config.icon,
                checked,
                cardClass: checked ? 'action-card action-card-checked' : 'action-card',
                cardStyle: '',
                iconStyle: `background: linear-gradient(135deg, ${config.color}22, ${config.color}11); border: 1px solid ${config.color}33;`,
                labelColorStyle: `color: ${config.color};`,
            };
        });
    }

    // ─── Lifecycle ───
    renderedCallback() {
        if (this.expanded && this.showOrb) {
            this._startSiriAnimation(SIRI_CANVAS_LARGE, 'siriCanvas');
        } else if (!this.expanded) {
            this._startSiriAnimation(SIRI_CANVAS_SMALL, 'siriCanvasSmall');
        }
    }

    disconnectedCallback() {
        this._cleanup();
    }

    // ─── Siri Wave Animation ───
    _startSiriAnimation(size, refName) {
        const canvas = this.refs[refName];
        if (!canvas) return;

        // Avoid re-initializing the same canvas
        if (this._currentCanvasSize === size && this._animFrame) return;
        if (this._animFrame) cancelAnimationFrame(this._animFrame);
        this._currentCanvasSize = size;

        const ctx = canvas.getContext('2d');
        const dpr = window.devicePixelRatio || 1;
        canvas.width = size * dpr;
        canvas.height = size * dpr;
        canvas.style.width = size + 'px';
        canvas.style.height = size + 'px';
        ctx.scale(dpr, dpr);

        const isSmall = size === SIRI_CANVAS_SMALL;

        const draw = () => {
            ctx.clearRect(0, 0, size, size);
            const cx = size / 2;
            const cy = size / 2;
            const isActive = this.state === 'listening';

            // Collapsed orb always gently pulses
            this._phase += isActive ? 0.04 : 0.015;
            const t = this._phase;
            const baseR = size * 0.28;
            const layerCount = isSmall ? 3 : 4;

            for (let layer = 0; layer < layerCount; layer++) {
                const alpha = isActive ? 0.15 - layer * 0.03 : 0.08 - layer * 0.015;
                const amp = isSmall
                    ? (2 + layer * 1.2)
                    : (isActive ? 8 + layer * 6 : 2 + layer * 1.5);
                const speed = 1 + layer * 0.3;
                const r = baseR + layer * (isSmall ? 5 : 12);

                ctx.beginPath();
                for (let a = 0; a <= Math.PI * 2; a += 0.02) {
                    const wave = Math.sin(a * 6 + t * speed) * amp * (isActive ? 1 : 0.4)
                        + Math.sin(a * 3 - t * speed * 0.7) * amp * 0.5 * (isActive ? 1 : 0.3);
                    const px = cx + Math.cos(a) * (r + wave);
                    const py = cy + Math.sin(a) * (r + wave);
                    if (a === 0) ctx.moveTo(px, py);
                    else ctx.lineTo(px, py);
                }
                ctx.closePath();

                const grad = ctx.createRadialGradient(cx, cy, baseR * 0.3, cx, cy, r + (isSmall ? 8 : 20));
                grad.addColorStop(0, `rgba(99, 102, 241, ${alpha * 2})`);
                grad.addColorStop(0.5, `rgba(139, 92, 246, ${alpha * 1.5})`);
                grad.addColorStop(1, `rgba(236, 72, 153, ${alpha})`);
                ctx.fillStyle = grad;
                ctx.fill();
            }

            // Core glow
            const coreGrad = ctx.createRadialGradient(cx, cy, 0, cx, cy, baseR * 0.8);
            coreGrad.addColorStop(0, 'rgba(139, 92, 246, 0.35)');
            coreGrad.addColorStop(0.5, 'rgba(99, 102, 241, 0.15)');
            coreGrad.addColorStop(1, 'rgba(99, 102, 241, 0)');
            ctx.beginPath();
            ctx.arc(cx, cy, baseR * 0.8, 0, Math.PI * 2);
            ctx.fillStyle = coreGrad;
            ctx.fill();

            this._animFrame = requestAnimationFrame(draw);
        };

        draw();
    }

    // ─── Voice Recognition ───
    handleMicClick() {
        if (this.state === 'idle') {
            this._startListening();
        } else if (this.state === 'listening') {
            this._stopListening();
        }
    }

    _startListening() {
        const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;
        if (!SpeechRecognition) {
            this._showToast('Error', 'Speech recognition is not supported in this browser. Please use Chrome.', 'error');
            return;
        }

        this.transcript = '';
        this.displayedTranscript = '';
        this.parsedActions = [];
        this.listenTime = 0;
        this.state = 'listening';

        this._recognition = new SpeechRecognition();
        this._recognition.continuous = true;
        this._recognition.interimResults = true;
        this._recognition.lang = 'en-US';

        this._recognition.onresult = (event) => {
            let finalTranscript = '';
            let interimTranscript = '';
            for (let i = 0; i < event.results.length; i++) {
                if (event.results[i].isFinal) {
                    finalTranscript += event.results[i][0].transcript;
                } else {
                    interimTranscript += event.results[i][0].transcript;
                }
            }
            this.transcript = finalTranscript + interimTranscript;
        };

        this._recognition.onerror = (event) => {
            console.error('Speech recognition error:', event.error);
            if (event.error !== 'aborted') {
                this._showToast('Voice Error', `Speech recognition error: ${event.error}`, 'error');
                this.state = 'idle';
            }
        };

        this._recognition.onend = () => {
            if (this.state === 'listening') {
                this._processTranscript();
            }
        };

        this._recognition.start();

        this._timerInterval = setInterval(() => {
            this.listenTime++;
        }, 1000);
    }

    _stopListening() {
        if (this._recognition) {
            this._recognition.stop();
        }
        clearInterval(this._timerInterval);
        this._processTranscript();
    }

    // ─── Transcript Processing ───
    _processTranscript() {
        if (!this.transcript || this.transcript.trim().length === 0) {
            this._showToast('No Input', 'No speech detected. Please try again.', 'warning');
            this.state = 'idle';
            return;
        }

        this.state = 'transcribing';
        this.displayedTranscript = '';
        this._typewriterIdx = 0;

        this._typewriterInterval = setInterval(() => {
            if (this._typewriterIdx < this.transcript.length) {
                this.displayedTranscript = this.transcript.substring(0, this._typewriterIdx + 1);
                this._typewriterIdx++;
            } else {
                clearInterval(this._typewriterInterval);
                // eslint-disable-next-line @lwc/lwc/no-async-operation
                setTimeout(() => {
                    this.state = 'parsing';
                    this._callAIParsing();
                }, 600);
            }
        }, 18);
    }

    // ─── AI Parsing via Apex ───
    async _callAIParsing() {
        try {
            const result = await parseVoiceInput({
                transcript: this.transcript,
                opportunityId: this.recordId,
                currentStage: this.oppStage,
                accountName: this.accountName
            });

            this.parsedActions = JSON.parse(result);
            this.state = 'confirming';
        } catch (error) {
            console.error('AI parsing error:', error);
            this._showToast('Parsing Error', error.body?.message || 'Failed to parse voice input', 'error');
            this.state = 'idle';
        }
    }

    // ─── Confirm & Execute ───
    async handleConfirm() {
        this.state = 'confirmed';
        this._confirmStartTime = Date.now();

        try {
            await executeActions({
                actionsJson: JSON.stringify(this.parsedActions),
                opportunityId: this.recordId
            });

            const elapsed = ((Date.now() - this._confirmStartTime) / 1000).toFixed(1);
            this.elapsedTime = elapsed;

            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => {
                this.state = 'done';
                this._showToast('Success', `${this.actionCount} actions applied to ${this.oppName}`, 'success');
                this._refreshRecordPage();
            }, this.parsedActions.length * 80 + 500);

        } catch (error) {
            console.error('Execute error:', error);
            this._showToast('Update Error', error.body?.message || 'Failed to execute actions', 'error');
            this.state = 'confirming';
        }
    }

    // ─── Reset ───
    handleReset() {
        this._cleanup();
        this.state = 'idle';
        this.transcript = '';
        this.displayedTranscript = '';
        this.parsedActions = [];
        this.listenTime = 0;
        this.elapsedTime = '0.0';
        this._currentCanvasSize = 0;

        // Auto-collapse after done
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            this.expanded = false;
        }, 300);
    }

    // ─── Helpers ───
    _cleanup() {
        if (this._recognition) {
            try { this._recognition.abort(); } catch (e) { /* ignore */ }
        }
        if (this._timerInterval) clearInterval(this._timerInterval);
        if (this._typewriterInterval) clearInterval(this._typewriterInterval);
        if (this._animFrame) {
            cancelAnimationFrame(this._animFrame);
            this._animFrame = null;
        }
    }

    _showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    _refreshRecordPage() {
        eval("$A.get('e.force:refreshView').fire()");
    }
}
