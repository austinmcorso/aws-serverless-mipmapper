import { Observable } from 'rxjs';
import { ajax } from 'rxjs/observable/dom/ajax';

import * as ActionTypes from '../action_types';
import actions from '../actions';
import config from '../config';

export default function imageUpload(action$) {
  return action$.ofType(ActionTypes.ADD_IMAGE_SUCCESS)
    .map(action => action.image)
    .switchMap(image =>
      ajax({
        method: 'POST',
        url: `${config.apiUrl}/images`,
        body: image,
        headers: {
          'Content-Type': 'image/png',
        },
        responseType: 'json',
        crossDomain: true,
      })
    )
    .map(res => res.response.id)
    .switchMap(id =>
      ajax({
        method: 'GET',
        url: `${config.s3Url}/images/sm/${id}.png`,
        crossDomain: true,
      })
      .retryWhen(errors => {
        return errors
          .scan((retryCount, err) => {
            console.log('retryCount', retryCount);
            console.log(err);
            if (err.status === 404 && retryCount < 3) return retryCount+1;
            throw err;
          }, 0);
      })
    )
    .map(res => actions.uploadImageSuccess(res.request.url))
    .catch(err => {
      console.log('err');
      actions.uploadImageFail(err);
    });
}
