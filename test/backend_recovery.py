from datetime import date
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import service
import todo_state
import todo_transaction
from todo_store import StoreError


class SimulatedPowerLoss(BaseException):
    pass


class RecoveryCase(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.base = Path(self.temporary.name)
        self.directory = self.base / 'vault'
        self.directory.mkdir()
        self.env = patch.dict(os.environ, {'XDG_STATE_HOME': str(self.base / 'state')})
        self.env.start()
        self.source = self.directory / 'a.md'
        self.target = self.directory / 'b.md'
        self.source.write_text('- [ ] completed task\n- [ ] next\n')
        self.target.write_text('# Destination\n')

    def tearDown(self):
        self.env.stop()
        self.temporary.cleanup()

    def call(self, op, **payload):
        return service.dispatch(dict(op=op, dir=str(self.directory), **payload))

    def complete_first(self):
        before = self.source.read_text()
        after = before.replace('[ ]', '[x]', 1)
        return self.call('write', path=str(self.source), expected=before, text=after,
                         completion={'line': 0, 'checked': True}, identity={'kind': 'edit', 'line': 0})

    def test_state_position_survives_requests_and_is_directory_scoped(self):
        position = {'path': str(self.source), 'taskIndex': 1, 'line': 1, 'text': 'next'}
        self.call('save_session', position=position)
        self.assertEqual(self.call('session')['position'], position)
        other = self.base / 'other'
        other.mkdir()
        self.assertIsNone(service.dispatch(dict(op='session', dir=str(other)))['position'])
        with self.assertRaises(todo_state.StateError):
            self.call('save_session', position={**position, 'taskIndex': -1})
        with self.assertRaises(StoreError):
            self.call('save_session', position={**position, 'path': str(self.base / 'outside.md')})
        self.assertEqual(self.call('session')['position'], position)

    def test_failed_second_move_write_rolls_back_documents_and_history(self):
        completed = self.complete_first()
        source_before, target_before = self.source.read_text(), self.target.read_text()
        real_write = todo_transaction.atomic_write
        def fail_source(path, text):
            if path == str(self.source):
                raise StoreError('Simulated disk error')
            real_write(path, text)
        with patch.object(todo_transaction, 'atomic_write', side_effect=fail_source):
            with self.assertRaises(StoreError):
                self.call('move', path=str(self.source), expected=source_before, line=0, target=str(self.target))
        self.assertEqual(self.source.read_text(), source_before)
        self.assertEqual(self.target.read_text(), target_before)
        self.assertEqual(self.call('summary')['closedToday'], 1)
        self.assertFalse(Path(todo_state.paths_for(str(self.directory)).journal).exists())
        self.call('undo', token=completed['undoToken'])
        self.assertEqual(self.call('summary')['closedToday'], 0)

    def test_restart_recovers_partial_move_without_losing_prior_completion(self):
        self.complete_first()
        source_before, target_before = self.source.read_text(), self.target.read_text()
        real_write = todo_transaction.atomic_write
        def crash_before_source(path, text):
            if path == str(self.source):
                raise SimulatedPowerLoss()
            real_write(path, text)
        with patch.object(todo_transaction, 'atomic_write', side_effect=crash_before_source):
            with self.assertRaises(SimulatedPowerLoss):
                self.call('move', path=str(self.source), expected=source_before, line=0, target=str(self.target))
        self.assertNotEqual(self.target.read_text(), target_before)
        self.call('scan')
        self.assertEqual(self.source.read_text(), source_before)
        self.assertEqual(self.target.read_text(), target_before)
        self.assertEqual(self.call('summary')['closedToday'], 1)

    def test_restart_finishes_history_when_documents_were_fully_saved(self):
        source_before = self.source.read_text()
        after = source_before.replace('[ ]', '[x]', 1)
        state_path = todo_state.paths_for(str(self.directory)).data
        real_json = todo_transaction.atomic_json
        def crash_before_history(path, value):
            if path == state_path:
                raise SimulatedPowerLoss()
            real_json(path, value)
        with patch.object(todo_transaction, 'atomic_json', side_effect=crash_before_history):
            with self.assertRaises(SimulatedPowerLoss):
                self.call('write', path=str(self.source), expected=source_before, text=after,
                          completion={'line': 0, 'checked': True}, identity={'kind': 'edit', 'line': 0})
        self.assertEqual(self.source.read_text(), after)
        self.assertEqual(self.call('summary')['closedToday'], 1)
        self.assertFalse(Path(todo_state.paths_for(str(self.directory)).journal).exists())

    def test_move_undo_refuses_external_destination_changes(self):
        before = self.source.read_text()
        moved = self.call('move', path=str(self.source), expected=before, line=0, target=str(self.target))
        source_after = self.source.read_text()
        self.target.write_text(self.target.read_text() + '\nExternal note\n')
        external = self.target.read_text()
        with self.assertRaises(StoreError):
            self.call('undo', token=moved['undoToken'])
        self.assertEqual(self.source.read_text(), source_after)
        self.assertEqual(self.target.read_text(), external)

    def test_streak_uses_local_dates_yesterday_grace_and_empty_denominator(self):
        class LocalDate(date):
            @classmethod
            def today(cls):
                return cls(2026, 1, 1)
        paths = todo_state.paths_for(str(self.directory))
        events = [{'id': str(i), 'active': True, 'date': day}
                  for i, day in enumerate(['2025-12-30', '2025-12-31'])]
        locked = todo_state.LockedState(paths, {'events': events})
        with patch.object(todo_state, 'date', LocalDate):
            metrics = todo_state.summary(locked, 0, 0)
            self.assertEqual((metrics['streak'], metrics['closedToday'], metrics['percent']), (2, 0, 0))
            locked.value['events'] += [
                {'id': 'today1', 'active': True, 'date': '2026-01-01'},
                {'id': 'today2', 'active': True, 'date': '2026-01-01'},
                {'id': 'undone', 'active': False, 'date': '2026-01-01'},
            ]
            metrics = todo_state.summary(locked, 3, 2)
            self.assertEqual((metrics['streak'], metrics['closedToday'], metrics['percent']), (3, 2, 66.7))
            locked.value['events'] = [{'id': 'old', 'active': True, 'date': '2025-12-28'}]
            self.assertEqual(todo_state.summary(locked, 1, 0)['streak'], 0)


if __name__ == '__main__':
    unittest.main()
