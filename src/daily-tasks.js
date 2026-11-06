import { randomUUID } from 'node:crypto';

export function validTaskDate(value) {
  return typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value) &&
    !Number.isNaN(Date.parse(value)) && new Date(value).toISOString().slice(0, 10) === value;
}

export function taskOccursOn(task, date) {
  if (!validTaskDate(date)) return false;
  if (task.schedule === 'date') return task.date === date;
  if (task.schedule === 'weekdays') return task.weekdays.includes(new Date(`${date}T00:00:00Z`).getUTCDay());
  return task.schedule === 'daily';
}

export function taskFields(body) {
  const title = typeof body.title === 'string' ? body.title.trim() : '';
  const note = typeof body.note === 'string' ? body.note.trim() : '';
  if (!title || title.length > 120 || note.length > 1000) throw new Error('Invalid title or note');
  if (typeof body.assigneeId !== 'string' || !body.assigneeId) throw new Error('Choose a member');
  if (!['daily', 'weekdays', 'date'].includes(body.schedule)) throw new Error('Invalid schedule');
  const weekdays = [...new Set(Array.isArray(body.weekdays) ? body.weekdays : [])];
  if (body.schedule === 'weekdays' && (!weekdays.length || weekdays.some((day) => !Number.isInteger(day) || day < 0 || day > 6))) throw new Error('Choose weekdays');
  if (body.schedule === 'date' && !validTaskDate(body.date)) throw new Error('Invalid date');
  if (!['anytime', 'time', 'period'].includes(body.timing)) throw new Error('Invalid timing');
  if (body.timing === 'time' && (typeof body.time !== 'string' || !/^([01]\d|2[0-3]):[0-5]\d$/.test(body.time))) throw new Error('Invalid time');
  if (body.timing === 'period' && !['morning', 'afternoon', 'evening', 'night'].includes(body.period)) throw new Error('Invalid period');
  return { title, note, assigneeId: body.assigneeId, schedule: body.schedule,
    weekdays: body.schedule === 'weekdays' ? weekdays : [], date: body.schedule === 'date' ? body.date : null,
    timing: body.timing, time: body.timing === 'time' ? body.time : null,
    period: body.timing === 'period' ? body.period : null };
}

export function registerDailyTaskRoutes(app, { db, requireAuth, requireHouseMember, asyncRoute, persistDbNow, changed }) {
  const middleware = [requireAuth, requireHouseMember];
  const fieldsFor = (req) => {
    const fields = taskFields(req.body);
    if (!req.house.members.some((member) => String(member.userId) === fields.assigneeId)) throw new Error('Member does not belong to this household');
    return fields;
  };
  app.get('/houses/:houseId/daily-tasks', ...middleware, (req, res) => {
    const date = req.query.date;
    if (!validTaskDate(date)) return res.status(400).json({ message: 'Invalid date' });
    res.json({ items: db.dailyTasks.filter((task) => task.houseId === req.house.id && taskOccursOn(task, date))
      .map((task) => ({ ...task, completed: task.completedDates.includes(date) })) });
  });
  app.post('/houses/:houseId/daily-tasks', ...middleware, asyncRoute(async (req, res) => {
    let fields;
    try { fields = fieldsFor(req); } catch (error) { return res.status(400).json({ message: error.message }); }
    const task = { ...fields, id: randomUUID(), houseId: req.house.id, createdBy: req.user.id,
      createdAt: new Date().toISOString(), completedDates: [] };
    db.dailyTasks.push(task);
    await persistDbNow();
    changed(req.house.id);
    res.status(201).json(task);
  }));
  app.put('/houses/:houseId/daily-tasks/:id', ...middleware, asyncRoute(async (req, res) => {
    const task = db.dailyTasks.find((item) => item.houseId === req.house.id && item.id === req.params.id);
    if (!task) return res.status(404).json({ message: 'Task not found' });
    if (task.createdBy !== req.user.id) return res.status(403).json({ message: 'Only the creator can edit this task' });
    let fields;
    try { fields = fieldsFor(req); } catch (error) { return res.status(400).json({ message: error.message }); }
    Object.assign(task, fields, { updatedAt: new Date().toISOString() });
    await persistDbNow();
    changed(req.house.id);
    res.json(task);
  }));
  app.post('/houses/:houseId/daily-tasks/:id/completion', ...middleware, asyncRoute(async (req, res) => {
    const task = db.dailyTasks.find((item) => item.houseId === req.house.id && item.id === req.params.id);
    if (!task) return res.status(404).json({ message: 'Task not found' });
    if (![task.createdBy, task.assigneeId].includes(req.user.id)) return res.status(403).json({ message: 'Only the assignee or creator can complete this task' });
    const { date, completed } = req.body;
    if (!validTaskDate(date) || !taskOccursOn(task, date) || typeof completed !== 'boolean') return res.status(400).json({ message: 'Invalid completion' });
    task.completedDates = task.completedDates.filter((day) => day !== date);
    if (completed) task.completedDates.push(date);
    await persistDbNow();
    changed(req.house.id);
    res.json({ ...task, completed });
  }));
  app.delete('/houses/:houseId/daily-tasks/:id', ...middleware, asyncRoute(async (req, res) => {
    const task = db.dailyTasks.find((item) => item.houseId === req.house.id && item.id === req.params.id);
    if (!task) return res.status(404).json({ message: 'Task not found' });
    if (task.createdBy !== req.user.id) return res.status(403).json({ message: 'Only the creator can delete this task' });
    db.dailyTasks.splice(db.dailyTasks.indexOf(task), 1);
    await persistDbNow();
    changed(req.house.id);
    res.json({ ok: true });
  }));
}
