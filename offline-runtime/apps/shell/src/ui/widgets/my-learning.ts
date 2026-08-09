import { html, nothing, type TemplateResult } from 'lit';
import type { MyLearningCourseDto } from '../apex-cache';

/** Vite catalog port for c/myLearning (My Learning tab / FlexiPage). */
export function renderMyLearning(opts: {
  label: string;
  courses: MyLearningCourseDto[] | null;
  cached?: boolean;
  selectedInstanceId?: string | null;
  onOpenCourse?: (instanceId: string) => void;
  onBackToCatalog?: () => void;
  onShowCertificate?: (instanceId: string) => void;
}): TemplateResult {
  const courses = opts.courses ?? [];
  const selected = opts.selectedInstanceId
    ? courses.find((c) => c.instanceId === opts.selectedInstanceId)
    : null;

  if (selected) {
    const progress = Math.round(Number(selected.progress ?? 0));
    return html`
      <div class="osr-lwc-mirror my-learning">
        <header class="ml-player-header">
          <button
            type="button"
            class="slds-button slds-button_neutral"
            @click=${() => opts.onBackToCatalog?.()}
          >
            ? Back
          </button>
          <div>
            <h1>${selected.title || 'Course'}</h1>
            <p class="ml-subtitle">${selected.status || 'In Progress'} · ${progress}% complete</p>
          </div>
        </header>
        <div class="ml-player-body">
          <p class="slds-text-color_weak">
            Course content opens from this catalog. Curriculum, video/PDF lessons, and quizzes sync with
            Learning Material Instances when online.
          </p>
          ${selected.canShowCertificate
            ? html`<button
                type="button"
                class="slds-button slds-button_brand slds-m-top_small"
                @click=${() => selected.instanceId && opts.onShowCertificate?.(selected.instanceId)}
              >
                View certificate
              </button>`
            : nothing}
        </div>
      </div>
    `;
  }

  return html`
    <div class="osr-lwc-mirror my-learning">
      <header class="catalog-header">
        <h1>
          ${opts.label || 'My Learning'}
          ${opts.cached ? html`<span class="osr-cache-pill">Cached</span>` : nothing}
        </h1>
        <p>Continue your assigned courses and track your progress.</p>
      </header>

      ${courses.length === 0
        ? html`<div class="empty-state">
            No learning modules are assigned to you yet. Ask your learning manager to assign a course.
          </div>`
        : html`<div class="course-grid">
            ${courses.map((course) => {
              const progress = Math.round(Number(course.progress ?? 0));
              return html`
                <article class="course-card">
                  <div class="course-card-body">
                    <h2>${course.title || 'Course'}</h2>
                    <p class="status">${course.status || 'Not Started'}</p>
                    <div class="progress-track" aria-hidden="true">
                      <div class="progress-fill" style=${`width:${progress}%`}></div>
                    </div>
                    <p class="progress-label">${progress}% complete</p>
                  </div>
                  <div class="course-card-actions">
                    <button
                      type="button"
                      class="slds-button slds-button_brand"
                      ?disabled=${!course.instanceId}
                      @click=${() => course.instanceId && opts.onOpenCourse?.(course.instanceId)}
                    >
                      Continue
                    </button>
                    ${course.canShowCertificate
                      ? html`<button
                          type="button"
                          class="slds-button slds-button_neutral"
                          @click=${() =>
                            course.instanceId && opts.onShowCertificate?.(course.instanceId)}
                        >
                          Certificate
                        </button>`
                      : nothing}
                  </div>
                </article>
              `;
            })}
          </div>`}
    </div>
  `;
}
